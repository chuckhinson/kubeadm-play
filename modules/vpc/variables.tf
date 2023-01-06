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
