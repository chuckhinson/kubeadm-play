# module cluster-network

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

data "aws_vpc" "main" {
  id = var.vpc_id
}

resource "aws_subnet" "private" {
  vpc_id = var.vpc_id
  cidr_block = var.private_subnet_cidr_block
  tags = {
    Name = "${var.resource_name}-private"
  }
}

resource "aws_route_table" "private" {
  vpc_id = var.vpc_id

  tags = {
    Name = "${var.resource_name}-private"
  }
}

resource "aws_route" "private-external" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = var.nat_gateway_id
}

## Not sure whether I'll actually need these, so leave commented out
## until I know for sure
# # These pod network route definitions are fragile as they assume that
# # pod networks are assigned in a certain order (i.e., all controllers 
# # and then all workers).  I also wonder if the CNI plugin would take care of this
# resource "aws_route" "kubeadm-private-controllers" {
#   # shouldnt we also include the controllers? Or are we making it so that
#   # pods cant run on controllers?
#   count = length(aws_instance.controllers[*].private_ip)
#   destination_cidr_block = "10.200.${count.index+10}.0/24"
#   instance_id = aws_instance.controllers[count.index].id
#   route_table_id         = aws_route_table.kubeadm-private.id
# }

# # These pod network route definitions are fragile as they assume that
# # pod networks are assigned in a certain order (i.e., all controllers 
# # and then all workers). I also wonder if the CNI plugin would take care of this
# resource "aws_route" "kubeadm-private-workers" {
#   # shouldnt we also include the controllers? Or are we making it so that
#   # pods cant run on controllers?
#   count = length(aws_instance.workers[*].private_ip)
#   destination_cidr_block = "10.200.${count.index+20}.0/24"
#   instance_id = aws_instance.workers[count.index].id
#   route_table_id         = aws_route_table.kubeadm-private.id
# }

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}


resource "aws_security_group" "cluster" {
  name        = "${var.resource_name}-cluster"
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
    Name = "${var.resource_name}-internal"
  }
}


resource "aws_instance" "controllers" {
  count = 3

  ami = var.node_ami_id
  associate_public_ip_address = false
  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = "50"
  }
  instance_type = "t3.small"
  key_name = var.instance_keypair_name
  private_ip =  cidrhost(var.private_subnet_cidr_block,10+count.index)
  source_dest_check = false
  subnet_id = aws_subnet.private.id
#  user_data = "name=controller-${count.index}"
  vpc_security_group_ids = [aws_security_group.cluster.id]

  tags = {
    Name = "controller-${count.index}"
  }
}

resource "aws_instance" "workers" {
  count = 3

  ami = var.node_ami_id
  associate_public_ip_address = false
  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = "50"
  }
  instance_type = "t3.small"
  key_name = var.instance_keypair_name
  private_ip =  cidrhost(var.private_subnet_cidr_block,20+count.index)
  source_dest_check = false
  subnet_id = aws_subnet.private.id
#  user_data = "name=worker-${count.index}|pod-cidr=10.200.${count.index}.0/24"
  vpc_security_group_ids = [aws_security_group.cluster.id]

  tags = {
    Name = "worker-${count.index}"
  }
}


