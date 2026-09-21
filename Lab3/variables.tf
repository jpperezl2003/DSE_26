variable "aws_profile" {
  description = "AWS CLI profile"
  type        = string
  default     = "academy"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "instance_name" {
  description = "Name of the EC2 instance and SSH key"
  type        = string
  default     = "lab3"
}

variable "ssh_cidr" {
  description = "CIDR opcional para SSH; null deshabilita el acceso SSH"
  type        = string
  default     = null
  validation {
    condition     = var.ssh_cidr == null ? true : can(cidrnetmask(var.ssh_cidr)) && var.ssh_cidr != "0.0.0.0/0"
    error_message = "Indica tu IP publica en formato IPv4/32 o una red restringida."
  }
}
variable "cpu_target" {
  description = "Objetivo de CPU promedio del Auto Scaling Group, en porcentaje"
  type        = number
  default     = 50

  validation {
    condition     = var.cpu_target >= 10 && var.cpu_target <= 90
    error_message = "El objetivo de CPU debe estar entre 10 y 90."
  }
}
