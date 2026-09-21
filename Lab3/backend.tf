terraform {
  backend "s3" {
    bucket       = "juanpablo.perez"
    key          = "lab3/terraform.tfstate"
    region       = "us-east-1"
    profile      = "academy"
    encrypt      = true
    use_lockfile = true
  }
}