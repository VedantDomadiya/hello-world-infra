terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0" # Consider updating to ~> 5.0 if compatible
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1" # Add random provider
    }
  }
  backend "s3" {
    bucket         = "my-s3-bucket-for-remote-backend" 
    key            = "hello-world-infra/terraform.tfstate"  
    region         = "ap-south-1"

    use_lockfile = true         # Usage of inbuilt of S3 Locking instead of DynamoDB Locking           
  }
}

provider "aws" {
  region = var.aws_region
}