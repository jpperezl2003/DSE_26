output "alb_url" {
  value = "http://${aws_lb.lab.dns_name}"
}
output "lambda_name" {
  value = aws_lambda_function.api.function_name
}

output "seed_result" {
  description = "Conteo de ventas y productos confirmado por la carga inicial."
  value       = jsondecode(aws_lambda_invocation.seed.result)
}
