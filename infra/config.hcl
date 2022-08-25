locals {

  config = "testing"

  testing = {
    aws_region     = "eu-west-1"
    account_name   = "testing"
    aws_account_id = "553688522943"
    aws_profile    = "leia-testing"
    bucket_suffix  = "github" 
    
    parameters = {
      ENVIRONMENT    = "testing"
      REGION         = "eu-west-1"
      DOMAIN         = "testing.dev.leiarenee.io"
      DNS_ZONE_ID    = "Z0890541BQO7OVB8F6WL"
      CLUSTER        = "my-testing-k8s"
      CERTIFICATE    = "arn:aws:acm:eu-west-1:377449198785:certificate/431ea958-254b-4f8c-995f-a311559fcce5"
      AWS_ACCOUNT_ID = "553688522943"
      PIPELINE_AWS_REGION = "eu-west-1"
      PIPELINE_AWS_ACCOUNT_ID = "377449198785"
      IAM_USER       = "cicd"
      REPO_REFERENCE = "main"
      TERRAFORM_VERSION = "1.2.7" 
      TERRAGRUNT_VERSION = "0.38.7" 

    }
  }

}