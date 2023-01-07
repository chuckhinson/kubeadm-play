variable "vpc_cidr_block" {
  nullable = false
  type = string
  description = "This is the CIDR block for the VPC"
}

variable "public_subnet_cidr_block" {
  nullable = false
  type = string
  description = "This is the CIDR block for the public subnet"
}

variable "resource_name" {
  nullable = false
  type = string
  description = "The value to use for resource names"
}

variable "jumpbox_ami_id" {
  nullable = false
  type = string
  description = "AMI to be used for jumpbox"
}

variable "instance_keypair_name" {
  nullable = false
  type = string
  description = "The name of the keypair to be used for the jumpbox"
}

variable "remote_access_cidr_block" {
  description = "The IP address of the (remote) server that is allowed to access the nodes (as a /32 CIDR block)"
}

variable "create_nat_gateway" {
  nullable = true
  default = false
  type = bool
  description = "boolean indicating whether a NAT gateway (with corresponding EIP) should be created in the public subnet"
}