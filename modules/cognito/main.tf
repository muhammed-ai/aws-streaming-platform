resource "aws_cognito_user_pool" "users" {
  name = "netflix-users-${var.env}"
}