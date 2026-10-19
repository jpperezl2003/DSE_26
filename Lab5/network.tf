data "aws_availability_zones" "available" { state = "available" }
resource "aws_vpc" "inventory" {
  cidr_block           = "10.50.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}
resource "aws_subnet" "private" {
  count             = 1
  vpc_id            = aws_vpc.inventory.id
  cidr_block        = cidrsubnet(aws_vpc.inventory.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
}
resource "aws_internet_gateway" "inventory" {
  vpc_id = aws_vpc.inventory.id
}
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.inventory.id
  cidr_block              = cidrsubnet(aws_vpc.inventory.cidr_block, 8, 10)
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.inventory.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.inventory.id
  }
}
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
