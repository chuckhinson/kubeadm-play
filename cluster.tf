#
# Terraform for deploying the compute and network resources needed for a k8s cluster
#
# Semi HA deployment (3 masters, but all in same subnet/az)
# - VPC with public and private subnets
# - cluster nodes all in private subnet
# - jumpbox and nat gateway in public subnet
# - inbound to cluster subnet only 22 (from jump box) and 6443 (from elb)


terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  profile = "k8splay"
  region = "us-east-2"
  default_tags {
    tags = {
      Environment = "kubeadm"
    }
  }  
}

# Most of these should probably be locals instead of variables since there are some
# places that we've hard-coded assumptions based on the default value
variable "node_vpc_cidr_block" {
  default = "10.2.0.0/16"
  description = "This is the CIDR block for the VPC where the cluster will live"
}
variable "cluster_cidr_block" {
  default = "10.200.0.0/16"
  description = "The CIDR block to be used for Cluster IP addresses"
}
variable "service_cidr_block" {
  default = "10.32.0.0/24"
  description = "The CIDR block to be used for Service Virtual IP addresses"
}

variable "mgmt_server_cidr_block" {
  description = "The IP address of the (remote) server that is allowed to access the nodes (as a /32 CIDR block)"
}

locals {
  public_subnet_cidr_block = cidrsubnet(var.node_vpc_cidr_block,8,1)
  private_subnet_cidr_block = cidrsubnet(var.node_vpc_cidr_block,8,2)
}

module "vpc" {
  source = "./modules/vpc"

  vpc_cidr_block = var.node_vpc_cidr_block
  public_subnet_cidr_block = local.public_subnet_cidr_block
  resource_name = "kubeadm"
}

resource "aws_nat_gateway" "kubeadm" {
  allocation_id = aws_eip.kubeadm.id
  subnet_id     = module.vpc.public_subnet_id

  tags = {
    Name = "kubeadm"
  }
}

resource "aws_eip" "kubeadm" {
  vpc = true
}


resource "aws_subnet" "kubeadm-private" {
  vpc_id = module.vpc.vpc_id
  cidr_block = local.private_subnet_cidr_block
  tags = {
    Name = "kubeadm-private"
  }
}

resource "aws_route_table" "kubeadm-private" {
  vpc_id = module.vpc.vpc_id

  tags = {
    Name = "kubeadm-private"
  }
}

resource "aws_route" "kubeadm-private-external" {
  route_table_id         = aws_route_table.kubeadm-private.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_nat_gateway.kubeadm.id
}

# These pod network route definitions are fragile as they assume that
# pod networks are assigned in a certain order (i.e., all controllers 
# and then all workers).  I also wonder if the CNI plugin would take care of this
resource "aws_route" "kubeadm-private-controllers" {
  # shouldnt we also include the controllers? Or are we making it so that
  # pods cant run on controllers?
  count = length(aws_instance.controllers[*].private_ip)
  destination_cidr_block = "10.200.${count.index+10}.0/24"
  instance_id = aws_instance.controllers[count.index].id
  route_table_id         = aws_route_table.kubeadm-private.id
}

# These pod network route definitions are fragile as they assume that
# pod networks are assigned in a certain order (i.e., all controllers 
# and then all workers). I also wonder if the CNI plugin would take care of this
resource "aws_route" "kubeadm-private-workers" {
  # shouldnt we also include the controllers? Or are we making it so that
  # pods cant run on controllers?
  count = length(aws_instance.workers[*].private_ip)
  destination_cidr_block = "10.200.${count.index+20}.0/24"
  instance_id = aws_instance.workers[count.index].id
  route_table_id         = aws_route_table.kubeadm-private.id
}

resource "aws_security_group" "kubeadm-internal" {
  name        = "kubeadm-internal"
  description = "Allow cluster inbound traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description      = "Node network"
    protocol         = "-1"
    from_port        = 0
    to_port          = 0
    cidr_blocks      = [var.node_vpc_cidr_block]
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
    Name = "kubeadm-internal"
  }
}

resource "aws_security_group" "kubeadm-remote" {
  name        = "kubeadm-remote"
  description = "Allow remote access to cluster"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description      = "ssh from mgmt server"
    protocol         = "tcp"
    from_port        = "22"
    to_port          = "22"
    cidr_blocks      = [var.mgmt_server_cidr_block]
  }
  ingress {
    description      = "internal https from mgmt server"
    protocol         = "tcp"
    from_port        = "6443"
    to_port          = "6443"
    cidr_blocks      = [var.mgmt_server_cidr_block]
  }
  ingress {
    description      = "https from mgmt server"
    protocol         = "tcp"
    from_port        = "443"
    to_port          = "443"
    cidr_blocks      = [var.mgmt_server_cidr_block]
  }
  ingress {
    description      = "icmp from mgmt server"
    protocol         = "icmp"
    from_port        = "-1"
    to_port          = "-1"
    cidr_blocks      = [var.mgmt_server_cidr_block]
  }

  tags = {
    Name = "kubeadm-remote"
  }
}


data "aws_ami" "ubuntu_jammy" {
  most_recent      = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name = "architecture"
    values = ["x86_64"]
  }

  owners = ["099720109477"]  # amazon
}

resource "aws_instance" "kubeadm-jumpbox" {
  ami           = data.aws_ami.ubuntu_jammy.id
  associate_public_ip_address = true
  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = "50"
  }
  instance_type = "t3.micro"
  key_name = "k8splay"
  private_ip =  cidrhost(local.public_subnet_cidr_block,10)
  source_dest_check = false
  subnet_id = module.vpc.public_subnet_id
  vpc_security_group_ids = [aws_security_group.kubeadm-internal.id, aws_security_group.kubeadm-remote.id]

  tags = {
    Name = "kubeadm-jumpbox"
  }
}

resource "aws_instance" "controllers" {
  count = 3

  ami           = data.aws_ami.ubuntu_jammy.id
  associate_public_ip_address = false
  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = "50"
  }
  instance_type = "t3.micro"
  key_name = "k8splay"
  private_ip =  cidrhost(local.private_subnet_cidr_block,10+count.index)
  source_dest_check = false
  subnet_id = aws_subnet.kubeadm-private.id
#  user_data = "name=controller-${count.index}"
  vpc_security_group_ids = [aws_security_group.kubeadm-internal.id]

  tags = {
    Name = "controller-${count.index}"
  }
}

resource "aws_instance" "workers" {
  count = 3

  ami           = data.aws_ami.ubuntu_jammy.id
  associate_public_ip_address = false
  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = "50"
  }
  instance_type = "t3.micro"
  key_name = "k8splay"
  private_ip =  cidrhost(local.private_subnet_cidr_block,20+count.index)
  source_dest_check = false
  subnet_id = aws_subnet.kubeadm-private.id
#  user_data = "name=worker-${count.index}|pod-cidr=10.200.${count.index}.0/24"
  vpc_security_group_ids = [aws_security_group.kubeadm-internal.id]

  tags = {
    Name = "worker-${count.index}"
  }
}

resource "aws_lb" "kubeadm-api" {
  name               = "kubeadm-api"
  internal           = false
  load_balancer_type = "network"
  subnets            = [module.vpc.public_subnet_id]
}

resource "aws_lb_target_group" "kubeadm-api" {
  name        = "kubeadm-api"
  port        = 6443
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_lb_target_group_attachment" "kubeadm-api" {
  count = length(aws_instance.controllers[*].private_ip)

  target_group_arn = aws_lb_target_group.kubeadm-api.arn
  target_id        = aws_instance.controllers[count.index].private_ip
  port             = 6443
}

resource "aws_lb_listener" "kubeadm-api" {
  load_balancer_arn = aws_lb.kubeadm-api.arn
  port              = "443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kubeadm-api.arn
  }
}