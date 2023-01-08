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


module "vpc" {
  source = "./modules/vpc"

  vpc_cidr_block = var.node_vpc_cidr_block
  public_subnet_cidr_block = local.public_subnet_cidr_block
  resource_name = "kubeadm"
  jumpbox_ami_id = data.aws_ami.ubuntu_jammy.id
  instance_keypair_name = "k8splay"
  remote_access_cidr_block = var.mgmt_server_cidr_block
  create_nat_gateway = true

}

module "cluster-network" {
  source = "./modules/cluster-network"

  vpc_id = module.vpc.vpc_id
  nat_gateway_id = module.vpc.nat_gateway_id
  private_subnet_cidr_block = local.private_subnet_cidr_block
  resource_name = "kubeadm"
  node_ami_id = data.aws_ami.ubuntu_jammy.id
  instance_keypair_name = "k8splay"
  cluster_cidr_block = var.cluster_cidr_block

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
  count = length(module.cluster-network.controller_ips)

  target_group_arn = aws_lb_target_group.kubeadm-api.arn
  target_id        = module.cluster-network.controller_ips[count.index]
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
