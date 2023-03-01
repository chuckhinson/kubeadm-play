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
  profile = var.aws_profile_name
  region = var.aws_region
  default_tags {
    tags = {
      Environment = var.cluster_name
    }
  }  
}

variable "cluster_name" {
  nullable = false
  description = "The cluster name - will be used in the names of all resources.  This must be the cluster name as provided to kubespray in order for the cloud-controller manager to work properly"
}

variable "aws_profile_name" {
  nullable = false
  description = "That name of the aws profile to be use when access AWS APIs"
}

variable "aws_region" {
  # per https://github.com/hashicorp/terraform-provider-aws/issues/7750 the aws provider is not
  # using the region defined in aws profile, so it will need to be specified
  nullable = false
  description = "The region to operate in"
}

variable "ec2_keypair_name" {
  nullable = false
  description = "The name of the AWS Ec2 keypair to use to access ec2 instaces"
}

variable "remote_access_address" {
  description = "The IP address of the (remote) server that is allowed to access the nodes (as a /32 CIDR block)"
}

variable "node_vpc_cidr_block" {
  default = "10.2.0.0/16"
  description = "This is the CIDR block for the VPC where the cluster will live"
}

variable "cluster_cidr_block" {
  default = "10.200.0.0/16"
  description = "The CIDR block to be used for Cluster IP addresses"
}

variable "controller_instance_count" {
  nullable = true
  default = 3
  description = "The number of controller nodes"
}

variable "worker_instance_count" {
  nullable = true
  default = 3
  description = "The number of worker nodes"
}

variable "node_ami_owner_id" {
  # amazon commercial = 099720109477
  # amazon gov cloud = 513442679011
  default = null
  nullable = true
  type = string
  description = <<EOT
  Owner id to use when searching for ami to be used as node base image.  Normally
  prefer images owned by amazon vs aws-marketplace. If null, only images owned by
  the current account will be considered
  EOT
}


locals {
  public_subnet_cidr_block = cidrsubnet(var.node_vpc_cidr_block,8,1)
  private_subnet_cidr_block = cidrsubnet(var.node_vpc_cidr_block,8,2)
}

data "aws_caller_identity" "current" {}

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

  owners = [var.node_ami_owner_id]  # amazon
}

data "aws_ami" "ubuntu_containerd" {
  most_recent      = true

  filter {
    name   = "name"
    values = ["kube-ubuntu-22.04-*"]
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

  owners = [data.aws_caller_identity.current.account_id]

}

module "vpc" {
  source = "./modules/vpc"

  vpc_cidr_block = var.node_vpc_cidr_block
  public_subnet_cidr_block = local.public_subnet_cidr_block
  cluster_name = var.cluster_name
  jumpbox_ami_id = data.aws_ami.ubuntu_jammy.id
  instance_keypair_name = var.ec2_keypair_name
  remote_access_cidr_block = var.remote_access_address
  create_nat_gateway = true

}

module "iam" {
  source = "./modules/iam"

  cluster_name = var.cluster_name
}

module "cluster" {
  source = "./modules/cluster"

  vpc_id = module.vpc.vpc_id
  nat_gateway_id = module.vpc.nat_gateway_id
  private_subnet_cidr_block = local.private_subnet_cidr_block
  cluster_name = var.cluster_name
  node_ami_id = data.aws_ami.ubuntu_containerd.id
  instance_keypair_name = var.ec2_keypair_name
  cluster_cidr_block = var.cluster_cidr_block
  controller_instance_count = var.controller_instance_count
  worker_instance_count = var.worker_instance_count
  node_instance_profile_name = module.iam.node_instance_profile_name

}


resource "aws_lb" "cluster-api" {
  name               = "${var.cluster_name}-cluster-api"
  internal           = false
  load_balancer_type = "network"
  subnets            = [module.vpc.public_subnet_id]
}

resource "aws_lb_target_group" "cluster-api" {
  name        = "${var.cluster_name}-cluster-api"
  port        = 6443
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_lb_target_group_attachment" "cluster-api" {
  count = length(module.cluster.controller_nodes)

  target_group_arn = aws_lb_target_group.cluster-api.arn
  target_id        = module.cluster.controller_nodes[count.index].private_ip
  port             = 6443
}

resource "aws_lb_listener" "cluster-api" {
  load_balancer_arn = aws_lb.cluster-api.arn
  port              = "6443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.cluster-api.arn
  }
}

resource "aws_lb_target_group" "cluster-ingress" {
  name        = "${var.cluster_name}-cluster-ingress"
  port        = 443
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_lb_target_group_attachment" "cluster-ingress" {
  count = length(module.cluster.worker_nodes)

  target_group_arn = aws_lb_target_group.cluster-ingress.arn
  target_id        = module.cluster.worker_nodes[count.index].private_ip
  port             = 443
}

resource "aws_lb_listener" "cluster-ingress" {
  load_balancer_arn = aws_lb.cluster-api.arn
  port              = "443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.cluster-ingress.arn
  }
}
