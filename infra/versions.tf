terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
  # Optional but recommended: remote state. Fill in and uncomment.
  # backend "s3" {
  #   bucket         = ""   # your state bucket
  #   key            = "fastapi-cicd/terraform.tfstate"
  #   region         = ""
  #   dynamodb_table = ""   # for state locking
  # }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = { Project = var.project, ManagedBy = "terraform" }
  }
}

data "aws_caller_identity" "me" {}
