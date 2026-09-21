output "load_balancer_url" {
  description = "URL publica del balanceador"
  value       = "http://${aws_lb.lab3.dns_name}"
}

output "autoscaling_group_name" {
  description = "Grupo que administra las instancias dinamicamente"
  value       = aws_autoscaling_group.lab3.name
}

output "target_group_arn" {
  value = aws_lb_target_group.nginx.arn
}

output "ssh_user" {
  value = "ec2-user"
}

