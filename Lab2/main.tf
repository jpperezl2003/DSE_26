locals {
  lab2_subnet_ids = [
    data.aws_subnet.lab2["us-east-1a"].id,
    data.aws_subnet.lab2["us-east-1b"].id
  ]
}

#Instancia lab2_ec2

resource "aws_instance" "lab2_ec2" {
  count = 2

  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  subnet_id                   = local.lab2_subnet_ids[count.index]
  key_name = aws_key_pair.this.key_name
  associate_public_ip_address = true

  vpc_security_group_ids = [
    aws_security_group.lab2_sg.id
  ]

  user_data = file("${path.module}/user_data.sh")

  tags = {
    Name    = "lab2-ec2-${count.index + 1}"
    Project = "lab2"
  }
}              

#Security group 

resource "aws_security_group" "lab2_sg" {
  name        = "lab2-security-group"
  description = "Security group for Lab 2 EC2 instance"
  vpc_id      = data.aws_subnet.lab2["us-east-1a"].vpc_id


  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr]
  }

  ingress {
    description = "HTTP desde el balanceador"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    security_groups = [aws_security_group.alb_sg.id]

  }


  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }



  tags = {
    Name    = "lab2-sg"
    Project = "lab2"
  }
}

resource "aws_security_group" "alb_sg" {
  name        = "lab2-alb-sg"
  description = "HTTP para el balanceador"
  vpc_id      = data.aws_subnet.lab2["us-east-1a"].vpc_id

  ingress {
    description = "HTTP desde internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "lab2" {
  name               = "lab2-alb"
  internal           = false
  load_balancer_type = "application"

  security_groups = [aws_security_group.alb_sg.id]
  subnets         = local.lab2_subnet_ids
}

resource "aws_lb_target_group" "nginx" {
  name        = "lab2-nginx"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = data.aws_subnet.lab2["us-east-1a"].vpc_id
  health_check {
    path    = "/"
    matcher = "200"
  }
}

resource "aws_lb_target_group_attachment" "nginx" {
  count = length(aws_instance.lab2_ec2)
  target_group_arn = aws_lb_target_group.nginx.arn
  target_id        = aws_instance.lab2_ec2[count.index].id
  port             = 80
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.lab2.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nginx.arn
  }
}

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