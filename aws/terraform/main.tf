# Find a current Ubuntu 22.04 LTS x86_64 AMI published by Canonical.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
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

# Select an available Availability Zone in the chosen region.
data "aws_availability_zones" "available" {
  state = "available"
}

# Create a dedicated network for this lab.
resource "aws_vpc" "lab" {
  cidr_block           = "10.40.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "${var.project_name}-vpc"
    Project = var.project_name
  }
}

# Create a subnet for the Linux server.
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = "10.40.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name    = "${var.project_name}-public-subnet"
    Project = var.project_name
  }
}

# Provide internet connectivity to the public subnet.
resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name    = "${var.project_name}-igw"
    Project = var.project_name
  }
}

# Route internet-bound traffic through the internet gateway.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }

  tags = {
    Name    = "${var.project_name}-public-rt"
    Project = var.project_name
  }
}

# Associate the public route table with the subnet.
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Allow SSH only from the trusted public IPv4 address supplied in terraform.tfvars.
resource "aws_security_group" "linux" {
  name_prefix = "${var.project_name}-"
  description = "Restricted SSH access for the Linux hardening lab"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description = "SSH from the trusted administrator IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.trusted_ssh_cidr]
  }

  # Permit outbound traffic for package installation and system updates.
  egress {
    description = "Outbound IPv4 traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-sg"
    Project = var.project_name
  }
}

# Register the existing public key with AWS; never upload the private key.
resource "aws_key_pair" "admin" {
  key_name   = "${var.project_name}-admin"
  public_key = file(pathexpand(var.public_key_path))

  tags = {
    Project = var.project_name
  }
}

# Deploy the Ubuntu server that Ansible will harden.
resource "aws_instance" "linux" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.linux.id]
  key_name                    = aws_key_pair.admin.key_name
  associate_public_ip_address = true

  # Require IMDSv2 to reduce risks from instance metadata exposure.
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  # Use an encrypted general-purpose SSD for the operating system.
  root_block_device {
    volume_size           = 12
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name    = "${var.project_name}-ubuntu"
    Project = var.project_name
    Purpose = "Ansible Linux server hardening lab"
  }

  depends_on = [aws_route_table_association.public]
}
