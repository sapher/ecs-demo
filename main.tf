provider "aws" {
  region = var.region
}

data "aws_route53_zone" "this" {
  name = local.base_host
}

locals {
  base_host = "local.host"
}