terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "mock"
  secret_key                  = "mock"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

module "operations" {
  source = "../.."

  environment             = "ci"
  tags                    = {
    Project = "dpc-learning"
  }
  sns_topic_arn           = "arn:aws:sns:us-east-1:123456789012:dpc-learning-alerts"
  notify_lambda_arn       = "arn:aws:lambda:us-east-1:123456789012:function:dpc-notify"
  state_machine_arn       = "arn:aws:states:us-east-1:123456789012:stateMachine:dpc-pipeline"
  redshift_workgroup_name = "dpc-learning"
  email_subscribers       = ["alerts@example.com"]
  send_ok_actions         = true
}
