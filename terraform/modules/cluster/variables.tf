variable "vpc_id" {
  nullable = false
  type = string
  description = "This is the id for our VPC"
}

variable "resource_name" {
  nullable = false
  type = string
  description = "The value to use for resource names"
}

variable "nat_gateway_id" {
  nullable = false
  description = "id of NAT gateway that the private subnet can use for internet access"
}

variable "cluster_cidr_block" {
  nullable = false
  description = "CIDR block to be used for Cluser (Pod) IP addressess"
}

variable "private_subnet_cidr_block" {
  nullable = false
  type = string
  description = "This is the CIDR block for the private subnet where the cluster nodes live"
}

variable "node_ami_id" {
  nullable = false
  type = string
  description = "AMI to be used for cluster nodes (workers and controllers)"
}

variable "instance_keypair_name" {
  nullable = false
  type = string
  description = "The name of the keypair to be used for the cluster nodes"
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
