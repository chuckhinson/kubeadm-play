# module cluster-network

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}


resource "aws_subnet" "private" {
  vpc_id = var.vpc_id
  cidr_block = var.private_subnet_cidr_block
  tags = {
    Name = "${var.resource_name}-private"
  }
}

resource "aws_route_table" "private" {
  vpc_id = var.vpc_id

  tags = {
    Name = "${var.resource_name}-private"
  }
}

resource "aws_route" "private-external" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = var.nat_gateway_id
}

## Not sure whether I'll actually need these, so leave commented out
## until I know for sure
# # These pod network route definitions are fragile as they assume that
# # pod networks are assigned in a certain order (i.e., all controllers 
# # and then all workers).  I also wonder if the CNI plugin would take care of this
# resource "aws_route" "kubeadm-private-controllers" {
#   # shouldnt we also include the controllers? Or are we making it so that
#   # pods cant run on controllers?
#   count = length(aws_instance.controllers[*].private_ip)
#   destination_cidr_block = "10.200.${count.index+10}.0/24"
#   instance_id = aws_instance.controllers[count.index].id
#   route_table_id         = aws_route_table.kubeadm-private.id
# }

# # These pod network route definitions are fragile as they assume that
# # pod networks are assigned in a certain order (i.e., all controllers 
# # and then all workers). I also wonder if the CNI plugin would take care of this
# resource "aws_route" "kubeadm-private-workers" {
#   # shouldnt we also include the controllers? Or are we making it so that
#   # pods cant run on controllers?
#   count = length(aws_instance.workers[*].private_ip)
#   destination_cidr_block = "10.200.${count.index+20}.0/24"
#   instance_id = aws_instance.workers[count.index].id
#   route_table_id         = aws_route_table.kubeadm-private.id
# }

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}


