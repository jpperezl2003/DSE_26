output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.lab1_ec2.id
}

output "public_ip" {
  description = "Public IP address"
  value       = aws_instance.lab1_ec2.public_ip
}

output "public_dns" {
  description = "Public DNS name"
  value       = aws_instance.lab1_ec2.public_dns
}

output "ssh_user" {
  description = "SSH username for Amazon Linux 2023"
  value       = "ec2-user"
}

output "ssh_command" {
  value = "ssh -i ${var.instance_name}-key.pem ec2-user@${aws_instance.lab1_ec2.public_ip}"
}

output "website_url" {
  description = "Nginx website URL"
  value       = "http://${aws_instance.lab1_ec2.public_dns}"
}