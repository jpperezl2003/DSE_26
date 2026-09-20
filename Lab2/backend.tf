terraform {
  backend "s3" {
    bucket       = "juanpablo.perez"
    key          = "lab2/terraform.tfstate"
    region       = "us-east-1"
    profile      = "academy"
    encrypt      = true
    use_lockfile = true
  }
}