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

variable "private_subnet_cidr_block" {
  nullable = false
  type = string
  description = "This is the CIDR block for the private subnet"
}

