resource "aws_service_discovery_private_dns_namespace" "this" {
  name = "${var.env}-testing"
  vpc  = module.vpc.vpc_id
}
