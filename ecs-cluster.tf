resource "aws_ecs_cluster" "this" {
  name = "ecs-${var.env}"
}
