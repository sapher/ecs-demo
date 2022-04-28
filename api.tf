locals {
  api_host           = "api.${local.base_host}"
  api_container_port = 3000
  db_credentials = {
    "user" : "testing",
    "pass" : "testing", // for testing you know ?
    "name" : "testing"
  }
}

# Execution role
data "aws_iam_policy_document" "api-exec-role" {
  statement {
    sid     = "AssumeRole"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    effect = "Allow"
  }
}

resource "aws_iam_role" "api-exec-role" {
  name               = "${var.env}-api-exec-role"
  assume_role_policy = data.aws_iam_policy_document.api-exec-role.json
}

resource "aws_iam_role_policy_attachment" "api-exec-role" {
  role       = aws_iam_role.api-exec-role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task role
data "aws_iam_policy_document" "api-task-role" {
  statement {
    sid     = "AssumeRole"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    effect = "Allow"
  }
}

resource "aws_iam_role" "api-task-role" {
  name               = "${var.env}-api-task-role"
  assume_role_policy = data.aws_iam_policy_document.api-exec-role.json
}

# Network
resource "aws_security_group" "api" {
  name        = "${var.env}-api"
  description = "Allow access to load balancer"
  vpc_id      = module.vpc.vpc_id

  ingress {
    protocol         = "tcp"
    from_port        = local.api_container_port
    to_port          = local.api_container_port
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    protocol         = "-1"
    from_port        = 0
    to_port          = 0
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

# Service discovery
resource "aws_service_discovery_service" "api" {
  name = "api"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.this.id

    dns_records {
      ttl  = 10
      type = "A"
    }
  }
}

# Service
resource "aws_ecs_service" "api" {
  name                 = "api"
  cluster              = aws_ecs_cluster.this.id
  task_definition      = aws_ecs_task_definition.api.arn
  launch_type          = "FARGATE"
  desired_count        = 1
  force_new_deployment = true

  network_configuration {
    security_groups  = [aws_security_group.api.id]
    assign_public_ip = false
    subnets          = module.vpc.private_subnets
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.api.arn
    container_name   = "api"
    container_port   = local.api_container_port
  }

  service_registries {
    registry_arn   = aws_service_discovery_service.api.arn
    container_name = "api"
  }
}

# Logs
resource "aws_cloudwatch_log_group" "api" {
  name = "/fargate/service/api"
}

resource "aws_cloudwatch_log_group" "flyway" {
  name = "/fargate/service/flyway"
}

# ECR
data "aws_ecr_repository" "api" {
  name = "api"
}

data "aws_ecr_repository" "flyway" {
  name = "flyway"
}

# ECS task
resource "aws_ecs_task_definition" "api" {
  family                   = "service"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.api-exec-role.arn
  task_role_arn            = aws_iam_role.api-task-role.arn
  container_definitions = jsonencode([
    {
      name      = "api"
      image     = "${data.aws_ecr_repository.api.repository_url}:${var.api_image_tag}"
      essential = true
      portMappings = [
        {
          containerPort = local.api_container_port
          hostPort      = local.api_container_port
        }
      ]
      environment : [
        { name : "DB_USER", value : local.db_credentials.user },
        { name : "DB_PASS", value : local.db_credentials.pass },
        { name : "DB_NAME", value : local.db_credentials.name },
        { name : "DB_HOST", value : aws_db_instance.this.address }
      ]
      logConfiguration : {
        logDriver : "awslogs",
        options : {
          "awslogs-group" : aws_cloudwatch_log_group.api.name,
          "awslogs-region" : var.region,
          "awslogs-stream-prefix" : "ecs"
        }
      }
    },
    {
      name      = "flyway"
      image     = "${data.aws_ecr_repository.flyway.repository_url}:latest"
      essential = false
      environment = [
        {
          name : "FLYWAY_URL",
          value : "jdbc:postgresql://${aws_db_instance.this.endpoint}/${local.db_credentials.name}",
        },
        { name : "FLYWAY_PASSWORD", value : local.db_credentials.pass },
        { name : "FLYWAY_USER", value : local.db_credentials.user },
        { name : "FLYWAY_CONNECT_RETRIES", value : "60" }
      ]
      logConfiguration : {
        logDriver : "awslogs",
        options : {
          "awslogs-group" : aws_cloudwatch_log_group.flyway.name,
          "awslogs-region" : var.region,
          "awslogs-stream-prefix" : "ecs"
        }
      }
    }
  ])
}

# Load balancer
resource "aws_alb_target_group" "api" {
  name        = "${var.env}-api"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    enabled  = true
    protocol = "HTTP"
    matcher  = "200"
    path     = "/healthz"
  }
}

resource "aws_alb_listener" "api-http" {
  load_balancer_arn = aws_lb.this.id
  port              = 80
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_alb_target_group.api.id
    type             = "forward"
  }
}

# Certificate
resource "aws_acm_certificate" "api" {
  domain_name       = local.api_host
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "api" {
  certificate_arn = aws_acm_certificate.api.arn
  validation_record_fqdns = [
    aws_route53_record.api-validation.fqdn
  ]
}

resource "aws_route53_record" "api-validation" {
  name    = tolist(aws_acm_certificate.api.domain_validation_options)[0].resource_record_name
  type    = tolist(aws_acm_certificate.api.domain_validation_options)[0].resource_record_type
  zone_id = data.aws_route53_zone.this.zone_id
  records = [tolist(aws_acm_certificate.api.domain_validation_options)[0].resource_record_value]
  ttl     = "60"
}

# API Gateway
resource "aws_apigatewayv2_api" "api" {
  name                         = "${var.env}-api"
  description                  = "API for Gardenator"
  protocol_type                = "HTTP"
  disable_execute_api_endpoint = true

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["*"]
    allow_headers = ["*"]
  }
}

resource "aws_apigatewayv2_stage" "api-default" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.apigw.arn
    format          = "$context.identity.sourceIp $context.identity.caller $context.identity.user [$context.requestTime] \"$context.httpMethod $context.resourcePath $context.protocol\" $context.status $context.responseLength $context.requestId $context.extendedRequestId"
  }
}

resource "aws_apigatewayv2_domain_name" "api" {
  domain_name = local.api_host
  domain_name_configuration {
    certificate_arn = aws_acm_certificate.api.arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }

  depends_on = [
    aws_acm_certificate_validation.api
  ]
}

resource "aws_route53_record" "api" {
  name    = aws_apigatewayv2_domain_name.api.domain_name
  type    = "A"
  zone_id = data.aws_route53_zone.this.zone_id

  alias {
    name                   = aws_apigatewayv2_domain_name.api.domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.api.domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_apigatewayv2_api_mapping" "api" {
  api_id      = aws_apigatewayv2_api.api.id
  domain_name = aws_apigatewayv2_domain_name.api.id
  stage       = aws_apigatewayv2_stage.api-default.id
}

resource "aws_apigatewayv2_vpc_link" "api" {
  name               = "api"
  security_group_ids = [aws_security_group.api.id]
  subnet_ids         = module.vpc.private_subnets
}

resource "aws_apigatewayv2_integration" "api" {
  api_id               = aws_apigatewayv2_api.api.id
  integration_type     = "HTTP_PROXY"
  integration_uri      = aws_alb_listener.api-http.arn
  integration_method   = "ANY"
  passthrough_behavior = "WHEN_NO_MATCH"
  connection_type      = "VPC_LINK"
  connection_id        = aws_apigatewayv2_vpc_link.api.id
}

// Authorizer
resource "aws_apigatewayv2_authorizer" "api" {
  api_id           = aws_apigatewayv2_api.api.id
  authorizer_type  = "JWT"
  name             = "${var.env}-cognito"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.web.id]
    issuer   = "https://${aws_cognito_user_pool.this.endpoint}"
  }
}

resource "aws_apigatewayv2_route" "api" {
  api_id             = aws_apigatewayv2_api.api.id
  route_key          = "ANY /{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.api.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.api.id
}
