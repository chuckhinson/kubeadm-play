# module cluster-network

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

locals {
  # aws user data script for setting hostname to the FQDN private dns name of the instance
  # (as required by aws cloud provider)
  hostname_user_data =  <<EOF
#!/bin/bash
sudo hostnamectl set-hostname $(curl -s http://169.254.169.254/latest/meta-data/local-hostname)
EOF

}

data "aws_vpc" "main" {
  id = var.vpc_id
}

resource "aws_subnet" "private" {
  vpc_id = var.vpc_id
  cidr_block = var.private_subnet_cidr_block
  tags = {
    Name = "${var.cluster_name}-private"
  }
}

resource "aws_route_table" "private" {
  vpc_id = var.vpc_id

  tags = {
    Name = "${var.cluster_name}-private"
  }
}

resource "aws_route" "private-external" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = var.nat_gateway_id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}


resource "aws_security_group" "cluster" {
  name        = "${var.cluster_name}-cluster"
  description = "Allow cluster inbound traffic"
  vpc_id      = var.vpc_id

  ingress {
    description      = "Node network"
    protocol         = "-1"
    from_port        = 0
    to_port          = 0
    cidr_blocks      = [data.aws_vpc.main.cidr_block]
  }
  ingress {
    description      = "cluster network"
    protocol         = "-1"
    from_port        = 0
    to_port          = 0
    cidr_blocks      = [var.cluster_cidr_block]
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
    Name = "${var.cluster_name}-internal"
  }
}


resource "aws_instance" "controllers" {
  count = var.controller_instance_count

  ami = var.node_ami_id
  associate_public_ip_address = false
  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = "50"
    tags = {
      Name = "${var.cluster_name}-controller-${count.index}"
      Environment = var.cluster_name
    }
  }
  iam_instance_profile = var.node_instance_profile_name
  instance_type = "t3.medium"
  key_name = var.instance_keypair_name
  private_ip =  cidrhost(var.private_subnet_cidr_block,10+count.index)
  source_dest_check = false
  subnet_id = aws_subnet.private.id
  user_data = local.hostname_user_data
  vpc_security_group_ids = [aws_security_group.cluster.id]

  tags = {
    Name = "${var.cluster_name}-controller-${count.index}"
  }
}

resource "aws_instance" "workers" {
  count = var.worker_instance_count

  ami = var.node_ami_id
  associate_public_ip_address = false
  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = "50"
    tags = {
      Name = "${var.cluster_name}-worker-${count.index}"
      Environment = var.cluster_name
    }
  }
  iam_instance_profile = var.node_instance_profile_name
  instance_type = "t3.medium"
  key_name = var.instance_keypair_name
  private_ip =  cidrhost(var.private_subnet_cidr_block,20+count.index)
  source_dest_check = false
  subnet_id = aws_subnet.private.id
  user_data = local.hostname_user_data
  vpc_security_group_ids = [aws_security_group.cluster.id]

  tags = {
    Name = "${var.cluster_name}-worker-${count.index}"
  }
}


