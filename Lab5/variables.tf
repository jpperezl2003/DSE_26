variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "project_name" {
  type    = string
  default = "lab5-inventario"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,39}$", var.project_name))
    error_message = "Usa de 3 a 40 caracteres: letras minusculas, numeros y guiones."
  }
}
variable "minimum_stock" {
  type    = number
  default = 3
  validation {
    condition     = var.minimum_stock >= 0 && floor(var.minimum_stock) == var.minimum_stock
    error_message = "El stock minimo debe ser un entero no negativo."
  }
}

variable "grafana_allowed_cidr" {
  description = "Tu IP publica IPv4 con /32, autorizada a abrir Grafana"
  type        = string
  validation {
    condition     = can(cidrnetmask(var.grafana_allowed_cidr)) && endswith(var.grafana_allowed_cidr, "/32")
    error_message = "Usa una IPv4 publica con /32, por ejemplo 203.0.113.10/32."
  }
}

variable "grafana_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instancia compartida ClickHouse/Grafana x86_64, minimo 4 GiB"
  validation {
    condition     = contains(["t3.medium", "t3.large"], var.grafana_instance_type)
    error_message = "Usa t3.medium o t3.large (x86_64)."
  }
}

variable "lab_role_name" {
  type    = string
  default = "LabRole"
}
variable "lab_instance_profile_name" {
  type    = string
  default = "LabInstanceProfile"
}
