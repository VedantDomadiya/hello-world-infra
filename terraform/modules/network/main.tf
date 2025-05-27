# Get available AZs in the region
data "aws_availability_zones" "available" {
  state = "available"
}

# --- VPC ---
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
  }
}

# --- Internet Gateway ---
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
  }
}


# --- Public Subnets using for_each ---
resource "aws_subnet" "public" {
  for_each = var.public_subnets # Iterate over the map

  vpc_id                  = aws_vpc.main.id
  # Calculate CIDR block: e.g., if vpc_cidr_block is 10.0.0.0/16 and suffix is "0", newbits=8 -> 10.0.0.0/24
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, tonumber(each.value.cidr_suffix))
  availability_zone       = data.aws_availability_zones.available.names[each.value.az_index]
  map_public_ip_on_launch = true

  tags = merge(
    {
      Name = "${var.project_name}-public-subnet-${each.key}" # each.key is "public_a", "public_b"
    },
    each.value.tags, # Merge custom tags from variable
    {
      Environment = var.environment
    }
  )
}

# --- Public Route Table ---
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "${var.project_name}-public-rt"
    Environment = var.environment
  }
}

# --- Public Route Table Associations using for_each ---
resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public # Iterate over the created public subnets

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# --- Private Subnets using for_each ---
resource "aws_subnet" "private" {
  for_each = var.private_subnets

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, tonumber(each.value.cidr_suffix))
  availability_zone = data.aws_availability_zones.available.names[each.value.az_index]

  tags = merge(
    {
      Name = "${var.project_name}-private-subnet-${each.key}"
    },
    each.value.tags,
    {
      Environment = var.environment
    }
  )
}

# --- Elastic IP for NAT Gateway ---
resource "aws_eip" "nat" {
  # vpc = true is deprecated, use domain = "vpc"
  #domain     = "vpc"
  vpc = true
  depends_on = [aws_internet_gateway.main]

  tags = {
    Name        = "${var.project_name}-nat-eip"
    Environment = var.environment
  }
}

# --- NAT Gateway ---
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  # Place NAT GW in the first public subnet for simplicity
  subnet_id     = aws_subnet.public[keys(var.public_subnets)[0]].id # Takes the first public subnet by sorted key order

  tags = {
    Name        = "${var.project_name}-nat-gw"
    Environment = var.environment
  }

  depends_on = [aws_internet_gateway.main]
}

# --- Private Route Table ---
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name        = "${var.project_name}-private-rt"
    Environment = var.environment
  }
}

# --- Private Route Table Associations using for_each ---
resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}