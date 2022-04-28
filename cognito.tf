resource "aws_cognito_user_pool" "this" {
  name = "${var.env}-testing"
}

resource "aws_cognito_user_pool_client" "web" {
  user_pool_id = aws_cognito_user_pool.this.id
  name         = "web"
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]
}
