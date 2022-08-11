# ---------------------------------------------------------------------------------------------------------------------
# TERRAGRUNT CONFIGURATION
# Terragrunt is a thin wrapper for Terraform that provides extra tools for working with multiple Terraform modules,
# remote state, and locking: https://github.com/gruntwork-io/terragrunt
# ---------------------------------------------------------------------------------------------------------------------

locals {
  default_aws_region = "eu-west-1"
  scripts_folder = "scripts"
  all_commands=["apply", "plan","destroy","apply-all","plan-all","destroy-all"]

  # Automatically load account-level variables
  
  config_file = "${get_parent_terragrunt_dir()}/config.hcl"
  config = read_terragrunt_config(local.config_file)
  config_vars = local.config.locals
  environment = get_env("WORKSPACE_ID", local.config_vars.config)
  account = lookup(local.config_vars, local.environment, {})
  
  json_acc = jsonencode(local.account)
  tgpath = get_parent_terragrunt_dir()
  hclpath = path_relative_to_include()
  platform = get_platform()
  tg_command = get_terraform_command()
  aws_caller_identity_arn = get_aws_caller_identity_arn()
  aws_caller_identity_user_id = get_aws_caller_identity_user_id()
  
  # Extract the variables we need for easy access
  account_name = get_env("TARGET_AWS_ACCOUNT_NAME", local.account.account_name)
  account_id   = get_env("TARGET_AWS_ACCOUNT_ID", local.account.aws_account_id)
  aws_profile  = get_env("TARGET_AWS_PROFILE", local.account.aws_profile)
  bucket_suffix_pre  = get_env("BUCKET_SUFFIX", local.account.bucket_suffix)
  bucket_suffix = local.bucket_suffix_pre == "dev" || local.bucket_suffix_pre == "" ? "dev-${run_cmd("--terragrunt-quiet", "whoami")}" : local.bucket_suffix_pre
  aws_region   = get_env("TARGET_AWS_REGION", local.default_aws_region)
  assume_profile = lookup(local.account, "parent_profile", local.aws_profile)
  repository = get_env("REPOSITORY_FQDN", "local")

  common_inputs = {
    # aws_batch_id = get_env("AWS_BATCH_ID")
  }

  # Automatically load region-level variables
  region_config = lookup(read_terragrunt_config(find_in_parent_folders("region.hcl")).locals, local.aws_region, {})

  # Automatically load environment-level variables
  environment_config = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  
  # State file name
  state_bucket = "tfstate-${local.account_id}-${local.aws_region}-${local.environment}${(local.bucket_suffix != null && local.bucket_suffix != "") ? "-${local.bucket_suffix}" : ""}"
  
  # Confirmation dialog
  confirm = replace(run_cmd("${get_parent_terragrunt_dir()}/${local.scripts_folder}/confirm_account.sh", local.tgpath, local.hclpath, local.json_acc, local.platform, local.tg_command, local.aws_caller_identity_arn, local.aws_caller_identity_user_id, local.config_vars.config, local.aws_region, local.environment, local.state_bucket, local.bucket_suffix, local.account_name, local.account_id, local.aws_profile),"\n","")
  
}

# Generate an AWS provider block
generate "provider" {
  path      = "aws-provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.aws_region}"

  # Only these AWS Account IDs may be operated on by this template
  # allowed_account_ids = ["${local.account_id}"]
}

provider "aws" {
  alias = "eu-central-1"
  region = "eu-central-1"

}
EOF
}

# Generate common variables
generate "common_variables" {
  path      = "common_variables.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
variable "replace_variables" {
  description = ""
  type = any
  default = {}
}

variable "region" {
  description = "AWS Region"
  default = "${local.aws_region}"
}

variable "user_email" {
  description = "The e-mail of the participant"
  default = ""
}

variable "uuid" {
  description = "Automatically generated uuid for each session"
  default = ""
}

variable "aws_batch_id" {
  description = "aws batch id"
  default = ""
}

variable "common_tags" {
  type = map
  description = "Common tags"
  default = {}
}

EOF
}
# Configure Terragrunt to automatically store tfstate files in an S3 bucket
remote_state {
  backend = "s3"
  config = {
    encrypt        = true
    bucket         = local.state_bucket
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.aws_region
    profile        = local.assume_profile 
    dynamodb_table = "terraform-locks"
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

terraform {
  before_hook "before_hook_replace_variables" {
    commands     = local.all_commands
    execute      = ["${get_parent_terragrunt_dir()}/${local.scripts_folder}/replace.sh","$TF_VAR_replace_variables",".","self","yaml,yml,json,jsn","false",2,jsonencode(local.account.parameters)]
   }
   
  # before_hook "before_hook_copy_common_modules" {
  #   commands     = concat(local.all_commands, ["init", "init-all"])
  #   execute      = ["${get_parent_terragrunt_dir()}/scripts/copy-common-modules.sh", get_parent_terragrunt_dir()]
  #  }

  after_hook "after_hook_1" {
    commands     = local.all_commands
    execute      = ["${get_parent_terragrunt_dir()}/${local.scripts_folder}/job_complete.sh", path_relative_to_include()]
   }

  # before_hook "before_hook_refresh_kube_token" {
  #   commands     = concat(local.all_commands, ["init", "init-all"])
  #   execute      = ["${get_parent_terragrunt_dir()}/scripts/refresh-kube-token.sh", local.aws_profile, local.account.parameters.CLUSTER, local.account_id, local.aws_region]
  #  }

  extra_arguments "arguments" {
    commands = concat(local.all_commands, ["init", "init-all"])
    optional_var_files = ["inputs.tfvars.json"]
    env_vars = {
      TG_PARRENT_DIR=get_parent_terragrunt_dir()
      TG_MODULES_LIST=get_env("TG_MODULES_LIST", "")
      TG_MODULES_COUNT=get_env("TG_MODULES_COUNT", "")
      SQS_QUEUE_URL=get_env("SQS_QUEUE_URL", "")
      SQS_MESSAGE_GROUP_ID=get_env("SQS_MESSAGE_GROUP_ID", "")
      SQS_AWS_PROFILE=get_env("SQS_AWS_PROFILE", "")
      INITIAL_PROGRESS=get_env("INITIAL_PROGRESS", "")
      MODULES_FINAL_PROGRESS=get_env("MODULES_FINAL_PROGRESS", "")
      AWS_PROFILE=local.aws_profile
      AWS_DEFAULT_REGION=local.aws_region
      TF_PLUGIN_CACHE_DIR="${get_env("HOME")}/.terraform.d/plugin-cache"
    }
    arguments = ["-var","replace_variables=0"]
  }

}
# ---------------------------------------------------------------------------------------------------------------------
# GLOBAL PARAMETERS
# These variables apply to all configurations in this subfolder. These are automatically merged into the child
# `terragrunt.hcl` config via the include block.
# ---------------------------------------------------------------------------------------------------------------------

# Configure root level variables that all resources can inherit. This is especially helpful with multi-account configs
# where terraform_remote_state data sources are placed directly into the modules.
inputs = merge(
  local.account,
  local.region_config,
  local.environment_config,
  local.common_inputs,
  { common_tags = local.common_inputs }
)

# download_dir = "${get_parent_terragrunt_dir()}/.terragrunt-cache/${local.account_id}/${path_relative_to_include()}"
iam_role = lookup(local.account, "iam_role", null )