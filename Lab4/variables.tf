variable "allowed_cidr" {
  description = "CIDR IPv4 permitido para HTTP al ALB; por defecto acepta cualquier origen."
  type        = string
  default     = "0.0.0.0/0"
  validation {
    condition     = can(cidrnetmask(var.allowed_cidr))
    error_message = "Indica un CIDR IPv4 valido para acceder al ALB."
  }
}

variable "lambda_role_name" {
  type    = string
  default = "LabRole"
}


variable "cache_ttl" {
  type    = number
  default = 300
}

variable "aws_profile" {
  type    = string
  default = "academy"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}
