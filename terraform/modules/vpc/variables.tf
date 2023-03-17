variable "vpc_cidr_block" {
  nullable = false
  type = string
  default = ""
  description = <<EOT
  This is the CIDR block for the VPC.  If not specified, vpc_id must be specified.
  Ignored when vpc_id is specified
EOT
  validation {
    condition = (length(var.vpc_cidr_block) == 0) || (length(var.vpc_cidr_block) >= 9)
    error_message = "vpc_cidr_block does not appear to be in CIDR format of a.b.c.d/n"
  }
}

variable "vpc_id" {
  nullable = false
  type = string
  default = ""
  description = "Id of and existing VPC to be used.  If not spedified, vpc_cidr_block must be specified"
  validation {
    condition = (length(var.vpc_id) == 0) || (length(var.vpc_id) > 4 && substr(var.vpc_id, 0, 4) == "vpc-")
    error_message = "vpc_id is not empty and does not appear to be a valid vpc id"
  }
}

variable "cluster_name" {
  nullable = false
  type = string
  description = <<EOT
  The cluster name - will be used in the names of all resources.
  This must be the cluster name as provided to kubespray in order
  for the cloud-controller manager to work properly
EOT
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
  description = <<EOT
  boolean indicating whether a NAT gateway (with corresponding EIP) should
  be created in the public subnet
EOT
}
