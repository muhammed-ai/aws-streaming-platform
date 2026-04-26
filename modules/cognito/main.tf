# Cognito User Pool — manages user registration, login, and authentication for the Netflix clone
# Frontend uses this to authenticate users before they can access video content
resource "aws_cognito_user_pool" "users" {
  name = "netflix-users-${var.env}"
}
