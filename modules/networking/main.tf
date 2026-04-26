# VPC — isolated network for the Netflix clone infrastructure
# 10.1.0.0/16 gives 65,536 IP addresses across all subnets
resource "aws_vpc" "main" {
  cidr_block = "10.1.0.0/16"

  tags = {
    Name = "netflix-${var.env}-vpc"
  }
}

# Internet Gateway — allows resources in public subnets to communicate with the internet
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

# Public subnets (x2) — for resources that need direct internet access (e.g. load balancers)
# map_public_ip_on_launch gives each instance a public IP automatically
# Uses the VPC CIDR as base so changing the VPC range updates subnets automatically
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  map_public_ip_on_launch = true
}

# Private subnets (x2) — for resources that should not be directly reachable from the internet
# Offset by 10 to avoid overlapping with public subnet CIDRs
resource "aws_subnet" "private" {
  count      = 2
  vpc_id     = aws_vpc.main.id
  cidr_block = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index + 10)
}
