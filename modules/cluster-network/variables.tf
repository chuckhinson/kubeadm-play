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

variable "public_subnet_id" {
  nullable = false
  type = string
  description = "Subnet id of the public subnet"
}

variable "private_subnet_cidr_block" {
  nullable = false
  type = string
  description = "This is the CIDR block for the private subnet"
}

