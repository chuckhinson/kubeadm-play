Terraform module for creating the cluster network components

The VPC will have the following components
 - private subnet with route table incl route to NAT
 - worker and controller nodes
 - security group for nodes