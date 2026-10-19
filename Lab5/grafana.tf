data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}
resource "aws_security_group" "grafana" {
  name        = "${var.project_name}-grafana"
  description = "Grafana web access restricted to one public IPv4 address"
  vpc_id      = aws_vpc.inventory.id
  egress {
    description = "Package downloads and AWS HTTPS APIs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
locals {
  grafana_datasource = {
    apiVersion = 1
    datasources = [{
      name      = "Inventario ClickHouse"
      uid       = "clickhouse-inventory"
      type      = "grafana-clickhouse-datasource"
      access    = "proxy"
      isDefault = true
      editable  = false
      jsonData = {
        host            = "127.0.0.1"
        port            = 8123
        protocol        = "http"
        username        = "grafana_reader"
        defaultDatabase = "inventory"
        secure          = false
      }
    }]
  }
  grafana_dashboard_base = jsondecode(file("${path.module}/grafana/inventory-dashboard.json"))
  grafana_dashboard = merge(local.grafana_dashboard_base, {
    templating = { list = [merge(local.grafana_dashboard_base.templating.list[0], {
      query   = tostring(var.minimum_stock)
      current = { text = tostring(var.minimum_stock), value = tostring(var.minimum_stock) }
      options = [{ text = tostring(var.minimum_stock), value = tostring(var.minimum_stock), selected = true }]
    })] }
  })
  grafana_provider = {
    apiVersion = 1
    providers = [{
      name                  = "lab5"
      orgId                 = 1
      folder                = "Lab5"
      type                  = "file"
      disableDeletion       = true
      allowUiUpdates        = false
      updateIntervalSeconds = 30
      options               = { path = "/var/lib/grafana/dashboards" }
    }]
  }
}
resource "aws_instance" "grafana" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.grafana_instance_type
  subnet_id                   = aws_subnet.public.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.grafana.id]
  iam_instance_profile        = data.aws_iam_instance_profile.lab.name
  user_data_replace_on_change = true
  user_data_base64 = base64gzip(templatefile("${path.module}/grafana/user-data.sh.tftpl", {
    datasource_b64 = base64encode(jsonencode(local.grafana_datasource))
    dashboard_b64  = base64encode(jsonencode(local.grafana_dashboard))
    provider_b64   = base64encode(jsonencode(local.grafana_provider))
    schema_b64     = base64encode(file("${path.module}/sql/schema.sql"))
  }))
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  root_block_device {
    volume_size           = 24
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }
  tags       = { Name = "${var.project_name}-grafana" }
  depends_on = [aws_route_table_association.public]
}
resource "aws_eip" "grafana" {
  domain     = "vpc"
  instance   = aws_instance.grafana.id
  tags       = { Name = "${var.project_name}-grafana" }
  depends_on = [aws_internet_gateway.inventory]
}

resource "aws_vpc_security_group_ingress_rule" "grafana_web" {
  security_group_id = aws_security_group.grafana.id
  cidr_ipv4         = var.grafana_allowed_cidr
  from_port         = 3000
  to_port           = 3000
  ip_protocol       = "tcp"
}
