resource "aws_security_group" "processor" {
  name        = "${var.project_name}-processor"
  description = "Lambda connects to ClickHouse inside the VPC"
  vpc_id      = aws_vpc.inventory.id
}
resource "aws_vpc_security_group_egress_rule" "processor_database" {
  security_group_id            = aws_security_group.processor.id
  referenced_security_group_id = aws_security_group.grafana.id
  from_port                    = 8123
  to_port                      = 8123
  ip_protocol                  = "tcp"
}
resource "aws_vpc_security_group_ingress_rule" "clickhouse" {
  security_group_id            = aws_security_group.grafana.id
  referenced_security_group_id = aws_security_group.processor.id
  from_port                    = 8123
  to_port                      = 8123
  ip_protocol                  = "tcp"
  description                  = "Private ClickHouse ingestion from Lambda only"
}
