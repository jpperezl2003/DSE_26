data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["137112412989"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# Buscar la VPC predeterminada
data "aws_vpc" "default" {
  default = true
}

data "aws_subnet" "lab3" {
  for_each = toset(["${var.aws_region}a", "${var.aws_region}b"])

  availability_zone = each.value
  default_for_az    = true
  vpc_id            = data.aws_vpc.default.id
}