locals {
  lab3_subnet_ids = [
    data.aws_subnet.lab3["${var.aws_region}a"].id,
    data.aws_subnet.lab3["${var.aws_region}b"].id
  ]
}

#Security group 

resource "aws_security_group" "lab3_sg" {
  name        = "lab3-security-group"
  description = "Security group for Lab 3 EC2 instance"
  vpc_id      = data.aws_subnet.lab3["${var.aws_region}a"].vpc_id


  dynamic "ingress" {
    for_each = var.ssh_cidr == null ? [] : [var.ssh_cidr]
    content {
      description = "SSH opcional"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  ingress {
    description     = "HTTP desde el balanceador"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
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
    Name    = "lab3-sg"
    Project = "lab3"
  }
}

resource "aws_security_group" "alb_sg" {
  name        = "lab3-alb-sg"
  description = "HTTP para el balanceador"
  vpc_id      = data.aws_subnet.lab3["${var.aws_region}a"].vpc_id

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

resource "aws_lb" "lab3" {
  name               = "lab3-alb"
  internal           = false
  load_balancer_type = "application"

  security_groups = [aws_security_group.alb_sg.id]
  subnets         = local.lab3_subnet_ids
}

resource "aws_lb_target_group" "nginx" {
  name        = "lab3-nginx"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = data.aws_subnet.lab3["${var.aws_region}a"].vpc_id
  health_check {
    path    = "/"
    matcher = "200"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.lab3.arn
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

# Plantilla utilizada por Auto Scaling para crear todas las instancias.
resource "aws_launch_template" "lab3" {
  name_prefix   = "lab3-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.this.key_name
  user_data = base64encode(replace(
    file("${path.module}/user_data.sh"),
    "__LAB3_APP_BASE64__",
    filebase64("${path.module}/app.py")
  ))

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.lab3_sg.id]
    delete_on_termination       = true
  }

  monitoring {
    enabled = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 8
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "lab3-ec2"
      Project = "lab3"
    }
  }
}

resource "aws_autoscaling_group" "lab3" {
  name                      = "lab3-asg"
  min_size                  = 1
  desired_capacity          = 1
  max_size                  = 3
  vpc_zone_identifier       = local.lab3_subnet_ids
  target_group_arns         = [aws_lb_target_group.nginx.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300
  default_instance_warmup   = 180
  wait_for_elb_capacity     = 1
  wait_for_capacity_timeout = "15m"

  launch_template {
    id      = aws_launch_template.lab3.id
    version = aws_launch_template.lab3.latest_version
  }

  tag {
    key                 = "Project"
    value               = "lab3"
    propagate_at_launch = true
  }

  lifecycle {
    # AWS administra la capacidad deseada después del primer apply.
    ignore_changes = [desired_capacity]
  }

  depends_on = [aws_lb_listener.http]
}

resource "aws_autoscaling_policy" "cpu" {
  name                   = "lab3-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.lab3.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value     = var.cpu_target
    disable_scale_in = false
  }
}
