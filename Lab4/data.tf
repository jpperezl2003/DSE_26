data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_iam_role" "lab" {
  name = var.lambda_role_name
}
