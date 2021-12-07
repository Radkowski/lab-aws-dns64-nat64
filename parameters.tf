data "aws_availability_zones" "AZs" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}



variable "DeploymentRegion" {
  type = string
  default = "us-west-2"
}

variable "DeploymentName" {
  type = string
  default = "v6only"
}

variable "VPC_CIDR" {
  type = string
  default = "10.0.0.0/16"
}

variable "ALL_IPv4" {
  default = "0.0.0.0/0"
}

variable "ALL_IPv6" {
  default = "::/0"
}
