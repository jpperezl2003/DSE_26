resource "aws_kinesis_stream" "inventory" {
  name             = "${var.project_name}-events"
  shard_count      = 1
  retention_period = 24
  encryption_type  = "NONE"
  lifecycle {
    prevent_destroy = false
    ignore_changes  = [retention_period]
  }
  stream_mode_details {
    stream_mode = "PROVISIONED"
  }
}
resource "aws_cloudwatch_log_group" "processor" {
  name              = "/aws/lambda/${var.project_name}-processor"
  retention_in_days = 7
}
data "archive_file" "processor" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/processor.zip"
}
resource "aws_lambda_function" "processor" {
  function_name    = "${var.project_name}-processor"
  role             = data.aws_iam_role.lab.arn
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.processor.output_path
  source_code_hash = data.archive_file.processor.output_base64sha256
  timeout          = 180
  memory_size      = 256
  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.processor.id]
  }
  environment {
    variables = {
      CLICKHOUSE_URL = "http://${aws_instance.grafana.private_ip}:8123"
    }
  }
  depends_on = [aws_cloudwatch_log_group.processor, aws_vpc_security_group_ingress_rule.clickhouse,
  aws_vpc_security_group_egress_rule.processor_database]
}
resource "aws_lambda_event_source_mapping" "inventory" {
  event_source_arn                   = aws_kinesis_stream.inventory.arn
  function_name                      = aws_lambda_function.processor.arn
  starting_position                  = "TRIM_HORIZON"
  batch_size                         = 100
  maximum_batching_window_in_seconds = 5
  function_response_types            = ["ReportBatchItemFailures"]
  bisect_batch_on_function_error     = true
}
