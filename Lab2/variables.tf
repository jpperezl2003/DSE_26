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

variable "key_name" {
  description = "AWS EC2 key pair used for SSH"
  type        = string
  default     = "vockey"
}

variable "instance_name" {
  description = "Name of the EC2 instance and SSH key"
  type        = string
  default     = "lab2"
}

variable "ssh_cidr" {
  description = "CIDR allowed to connect by SSH"
  type        = string
  default     = "0.0.0.0/0"
}