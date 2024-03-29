# module vpc

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

#
# NOTE: we create either the data aws_vpc or the resource aws_vpc, but not both
# In order to make it easy on the rest of the code, we'll define locals that have
# the correct values regardles of we're using an existing vpc or no
#
locals {
  vpc_id         = var.vpc_id == "" ? aws_vpc.main[0].id : var.vpc_id
  vpc_cidr_block = var.vpc_id == "" ? var.vpc_cidr_block : data.aws_vpc.existing[0].cidr_block
  public_subnet_cidr_block = cidrsubnet(local.vpc_cidr_block,8,1)
}

data "aws_vpc" "existing" {
  # only create if we're using an existin vpc
  count = length(var.vpc_id) > 0 ? 1 : 0
  id = var.vpc_id
}

resource "aws_vpc" "main" {
  # only create if we're NOT using an existing vpc
  count = var.vpc_id == "" ? 1 : 0

  cidr_block = var.vpc_cidr_block
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name = var.cluster_name
  }

}

resource "aws_internet_gateway" "main" {
  vpc_id = local.vpc_id
  tags = {
    Name = var.cluster_name
  }
}

resource "aws_nat_gateway" "main" {
  count = var.create_nat_gateway ? 1 : 0
  allocation_id = aws_eip.main[0].id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = var.cluster_name
  }
}

resource "aws_eip" "main" {
  count = var.create_nat_gateway ? 1 : 0
  vpc = true
  tags = {
    Name = var.cluster_name
  }
}

resource "aws_subnet" "public" {
  vpc_id = local.vpc_id
  cidr_block = local.public_subnet_cidr_block
  tags = {
    Name = "${var.cluster_name}-public"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    "kubernetes.io/role/elb" = "1"
  }
  # Establish a way for external modules to depend on the igw
  # without having to expose the igw as an output
  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  vpc_id = local.vpc_id

  tags = {
    Name = "${var.cluster_name}-public"
  }
}

resource "aws_route" "public-external" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "main" {
  name        = "${var.cluster_name}-remote"
  description = "Allow remote access to cluster"
  vpc_id      = local.vpc_id

  ingress {
    description      = "ssh from mgmt server"
    protocol         = "tcp"
    from_port        = "22"
    to_port          = "22"
    cidr_blocks      = [var.remote_access_cidr_block]
  }
  ingress {
    description      = "internal https from mgmt server"
    protocol         = "tcp"
    from_port        = "6443"
    to_port          = "6443"
    cidr_blocks      = [var.remote_access_cidr_block]
  }
  ingress {
    description      = "https from mgmt server"
    protocol         = "tcp"
    from_port        = "443"
    to_port          = "443"
    cidr_blocks      = [var.remote_access_cidr_block]
  }
  ingress {
    description      = "icmp from mgmt server"
    protocol         = "icmp"
    from_port        = "-1"
    to_port          = "-1"
    cidr_blocks      = [var.remote_access_cidr_block]
  }
  # AWS normally provides a default egress rule, but terraform
  # deletes it by default, so we need to add it here to keep it
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }


  tags = {
    Name = "${var.cluster_name}-remote"
  }
}

resource "aws_instance" "jumpbox" {
  ami           = var.jumpbox_ami_id
  associate_public_ip_address = true
  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = "50"
    tags = {
      Name = "${var.cluster_name}-jumpbox"
      Environment = var.cluster_name
    }
  }
  instance_type = "t3.micro"
  key_name = var.instance_keypair_name
  private_ip =  cidrhost(local.public_subnet_cidr_block,10)
  source_dest_check = false
  subnet_id = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.main.id]

  tags = {
    Name = "${var.cluster_name}-jumpbox"
  }
}

