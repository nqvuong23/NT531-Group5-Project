terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    bucket  = "nt531-project-group5-bucket"
    key     = "terraform/terraform.tfstate"
    region  = "ap-southeast-1"
    profile = "dev"

    use_lockfile = true
    encrypt      = true
  }
}

# ------- Provider -------
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  # default_tags {
  #   tags = local.common_tags
  # }
}