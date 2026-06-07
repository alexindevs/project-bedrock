resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
 
  tags = {
    Name = "project-bedrock-vpc"
  }
}
 
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "project-bedrock-igw" }
}
 
locals {
  public_subnets = {
    "us-east-1a" = "10.0.0.0/20"
    "us-east-1b" = "10.0.16.0/20"
  }
  private_subnets = {
    "us-east-1a" = "10.0.32.0/20"
    "us-east-1b" = "10.0.48.0/20"
  }
}
 
resource "aws_subnet" "public" {
  for_each                = local.public_subnets
  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = true
 
  tags = {
    Name                                        = "project-bedrock-public-${each.key}"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}
 
resource "aws_subnet" "private" {
  for_each          = local.private_subnets
  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = each.key
 
  tags = {
    Name                                        = "project-bedrock-private-${each.key}"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "project-bedrock-nat-eip" }
}
 
resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public["us-east-1a"].id
  tags          = { Name = "project-bedrock-nat" }
  depends_on    = [aws_internet_gateway.this]
}
 
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = { Name = "project-bedrock-public-rt" }
}
 
resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }
  tags = { Name = "project-bedrock-private-rt" }
}
 
resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

locals {
  public_subnet_ids  = [for s in aws_subnet.public  : s.id]
  private_subnet_ids = [for s in aws_subnet.private : s.id]
}
