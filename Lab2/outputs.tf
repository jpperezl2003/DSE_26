output "instance_ids" {
  description = "IDs de las instancias EC2"
  value       = aws_instance.lab2_ec2[*].id
}

output "public_ips" {
  description = "IPs públicas de las instancias"
  value       = aws_instance.lab2_ec2[*].public_ip
}

output "public_dns" {
  description = "DNS públicos de las instancias"
  value       = aws_instance.lab2_ec2[*].public_dns
}

output "ssh_user" {
  description = "Usuario SSH para Amazon Linux 2023"
  value       = "ec2-user"
}

output "ssh_commands" {
  description = "Comando SSH para cada instancia"
  value = [
    for instance in aws_instance.lab2_ec2 :
    "ssh -i ${var.instance_name}-key.pem ec2-user@${instance.public_ip}"
  ]
}



output "load_balancer_url" {
  description = "URL del balanceador"
  value       = "http://${aws_lb.lab2.dns_name}"
}