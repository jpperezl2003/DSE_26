# Ejecutar la carga inicial una vez que RDS y Lambda esten disponibles.
# CREATE_ONLY evita ejecutar SQL durante terraform destroy.
resource "aws_lambda_invocation" "seed" {
  function_name   = aws_lambda_function.api.function_name
  lifecycle_scope = "CREATE_ONLY"
  input           = jsonencode({ action = "seed" })

  triggers = {
    database_id = aws_db_instance.lab.resource_id
    sql_hash    = filesha256("${path.module}/seed.sql")
    code_hash   = aws_lambda_function.api.source_code_hash
  }

  depends_on = [aws_lambda_function.api, aws_db_instance.lab]

  lifecycle {
    replace_triggered_by = [aws_lambda_function.api.id]
    postcondition {
      condition     = try(jsondecode(self.result).sales >= 100000 && jsondecode(self.result).products >= 100, false)
      error_message = "La carga inicial no confirmo las 100000 ventas y 100 productos. Revisa los logs de Lambda."
    }
  }
}
