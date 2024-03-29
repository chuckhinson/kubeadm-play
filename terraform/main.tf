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

provider "tls" {}

provider "null" {}

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
  nullable = false
  type = string
  default = "10.2.0.0/16"
  description = "This is the CIDR block for the VPC where the cluster will live.  If not specified, the vpc_id must be specified.  Ignored when vpc_id is specified"
  validation {
    condition = (length(var.node_vpc_cidr_block) == 0) || (length(var.node_vpc_cidr_block) >= 9)
    error_message = "vpc_cidr_block does not appear to be in CIDR format of a.b.c.d/n"
  }
}

variable "vpc_id" {
  nullable = false
  type = string
  default = ""
  description = "Id of an existing VPC to be used.  If not specified, vpc_cidr_block must be specified"
  validation {
    condition = (length(var.vpc_id) == 0) || (length(var.vpc_id) > 4 && substr(var.vpc_id, 0, 4) == "vpc-")
    error_message = "vpc_id is not null and does not appear to be a valid vpc id"
  }
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

resource null_resource "precheck" {
  lifecycle {
    precondition {
      condition = var.vpc_id != "" || (var.vpc_id == "" && var.node_vpc_cidr_block != "")
      error_message = "If vpc_id is not specificed, cidr_block must be specified"
    }
  }
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

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "ec2_keypair" {
  key_name   = var.cluster_name
  public_key = tls_private_key.ssh_key.public_key_openssh
}

module "vpc" {
  source = "./modules/vpc"

  vpc_cidr_block = var.node_vpc_cidr_block
  vpc_id = var.vpc_id
  cluster_name = var.cluster_name
  jumpbox_ami_id = data.aws_ami.ubuntu_jammy.id
  instance_keypair_name = aws_key_pair.ec2_keypair.key_name
  remote_access_cidr_block = var.remote_access_address
  create_nat_gateway = true

  # Make sure vpc_id and node_cidr_block are good before we try to use them
  depends_on = [null_resource.precheck]
}

module "iam" {
  source = "./modules/iam"

  cluster_name = var.cluster_name
}

module "cluster" {
  source = "./modules/cluster"

  vpc_id = module.vpc.vpc_id
  nat_gateway_id = module.vpc.nat_gateway_id
  private_subnet_cidr_block = cidrsubnet(module.vpc.vpc_cidr_block,8,2)
  cluster_name = var.cluster_name
  node_ami_id = data.aws_ami.ubuntu_containerd.id
  instance_keypair_name = aws_key_pair.ec2_keypair.key_name
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
