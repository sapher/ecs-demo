resource "aws_api_gateway_account" "this" {
  cloudwatch_role_arn = aws_iam_role.apigw-cw.arn
}

data "aws_iam_policy_document" "apig-cw-role" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      identifiers = ["apigateway.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_iam_role" "apigw-cw" {
  name               = "${var.env}-apigw"
  assume_role_policy = data.aws_iam_policy_document.apig-cw-role.json
}

resource "aws_cloudwatch_log_group" "apigw" {
  name = "/appgw"
}

data "aws_iam_policy_document" "apigw-cw-policy" {
  statement {
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
      "logs:GetLogEvents",
      "logs:FilterLogEvents"
    ]
  }
}

resource "aws_iam_role_policy" "apigw-cw" {
  name   = "default"
  role   = aws_iam_role.apigw-cw.id
  policy = data.aws_iam_policy_document.apigw-cw-policy.json
}
