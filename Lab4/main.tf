resource "random_password" "db" {
  length  = 32
  special = false
}
resource "random_password" "cache" {
  length  = 32
  special = false
}
resource "aws_vpc" "lab" {
  cidr_block           = "10.44.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}
resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id
}
resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.lab.id
  cidr_block        = cidrsubnet(aws_vpc.lab.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
}
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.lab.id
  cidr_block        = cidrsubnet(aws_vpc.lab.cidr_block, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }
}
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
resource "aws_security_group" "alb" {
  name_prefix = "lab4-alb-"
  vpc_id      = aws_vpc.lab.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }
}
resource "aws_security_group" "lambda" {
  name_prefix = "lab4-lambda-"
  vpc_id      = aws_vpc.lab.id
  egress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.lab.cidr_block]
  }
  egress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.lab.cidr_block]
  }
}
resource "aws_security_group" "db" {
  name_prefix = "lab4-db-"
  vpc_id      = aws_vpc.lab.id
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }
}
resource "aws_security_group" "cache" {
  name_prefix = "lab4-cache-"
  vpc_id      = aws_vpc.lab.id
  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }
}
resource "aws_db_subnet_group" "lab" {
  subnet_ids = aws_subnet.private[*].id
}
resource "aws_db_instance" "lab" {
  identifier                 = "dse-lab4-postgres"
  engine                     = "postgres"
  instance_class             = "db.t3.micro"
  allocated_storage          = 20
  storage_type               = "gp3"
  storage_encrypted          = true
  db_name                    = "lab4"
  username                   = "labadmin"
  password                   = random_password.db.result
  db_subnet_group_name       = aws_db_subnet_group.lab.name
  vpc_security_group_ids     = [aws_security_group.db.id]
  publicly_accessible        = false
  multi_az                   = false
  backup_retention_period    = 0
  skip_final_snapshot        = true
  deletion_protection        = false
  auto_minor_version_upgrade = true
}
resource "aws_elasticache_subnet_group" "lab" {
  name       = "dse-lab4-cache"
  subnet_ids = aws_subnet.private[*].id
}
resource "aws_elasticache_replication_group" "lab" {
  replication_group_id       = "dse-lab4-cache"
  description                = "Cache-aside para DSE Lab4"
  engine                     = "redis"
  engine_version             = "7.1"
  node_type                  = "cache.t3.micro"
  num_cache_clusters         = 1
  parameter_group_name       = "default.redis7"
  port                       = 6379
  subnet_group_name          = aws_elasticache_subnet_group.lab.name
  security_group_ids         = [aws_security_group.cache.id]
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.cache.result
  automatic_failover_enabled = false
  apply_immediately          = true
}
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/dse-lab4-api"
  retention_in_days = 7
}
resource "aws_lambda_function" "api" {
  function_name                  = "dse-lab4-api"
  role                           = data.aws_iam_role.lab.arn
  runtime                        = "python3.12"
  handler                        = "app.handler"
  filename                       = "${path.module}/build/lambda.zip"
  source_code_hash               = filebase64sha256("${path.module}/build/lambda.zip")
  timeout                        = 120 # Permite completar la carga inicial de seed.sql.
  memory_size                    = 512
  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }
  environment {
    variables = {
      DB_HOST     = aws_db_instance.lab.address
      DB_NAME     = aws_db_instance.lab.db_name
      DB_USER     = aws_db_instance.lab.username
      DB_PASSWORD = random_password.db.result
      CACHE_HOST  = aws_elasticache_replication_group.lab.primary_endpoint_address
      CACHE_TOKEN = random_password.cache.result
      CACHE_TTL   = tostring(var.cache_ttl)
    }
  }
  depends_on = [aws_cloudwatch_log_group.lambda]
}
resource "aws_lb" "lab" {
  name               = "dse-lab4-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
}
resource "aws_lb_target_group" "lambda" {
  name        = "dse-lab4-lambda"
  target_type = "lambda"
}
resource "aws_lambda_permission" "alb" {
  statement_id  = "AllowALB"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.lambda.arn
}
resource "aws_lb_target_group_attachment" "lambda" {
  target_group_arn = aws_lb_target_group.lambda.arn
  target_id        = aws_lambda_function.api.arn
  depends_on       = [aws_lambda_permission.alb]
}
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.lab.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lambda.arn
  }
}
