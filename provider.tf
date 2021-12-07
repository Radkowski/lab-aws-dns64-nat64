terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}


provider "aws" {
  region = var.DeploymentRegion
 #  assume_role {
 #   role_arn     = "XXXXXXXXX"
 #   session_name = "Teradmin-session"
 # }
}


variable "AWS_ACCESS_KEY_ID" {
  type    = string
}


variable "AWS_SECRET_ACCESS_KEY" {
  type    = string
}
