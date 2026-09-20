resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "this" {
  key_name   = "${var.instance_name}-key"
  public_key = tls_private_key.this.public_key_openssh
}

resource "local_sensitive_file" "private_key" {
  content  = tls_private_key.this.private_key_pem
  filename = "${path.module}/${var.instance_name}-key.pem"
}