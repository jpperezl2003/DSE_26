resource "aws_instance" "lab1_ec2" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  key_name = aws_key_pair.this.key_name
  associate_public_ip_address = true

  vpc_security_group_ids = [
    aws_security_group.lab1_sg.id
  ]

  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y nginx

              systemctl enable nginx
              systemctl start nginx

              cat > /usr/share/nginx/html/index.html <<'HTML'
              <!DOCTYPE html>
              <html>
              <head>
                  <title>Lab 1 - Terraform</title>
              </head>
              <body>
                  <h1>Hola desde Terraform!</h1>
                  <p>Servidor Nginx corriendo en AWS EC2.</p>
              </body>
              </html>
              HTML
              EOF

  tags = {
    Name    = "lab1-ec2"
    Project = "lab1"
  }
}