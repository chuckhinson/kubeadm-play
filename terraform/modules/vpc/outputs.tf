# This will always contain the correct vpc id regardless of whether we're using an
# existing vpc or creating a new vpc
output "vpc_id" {
  value = local.vpc_id
}

# This will always contain the correct vpc cidr block regardless of whether we're using
# an existing vpc or creating a new vpc
output "vpc_cidr_block" {
  value = local.vpc_cidr_block
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

output "nat_gateway_id" {
  value = one(aws_nat_gateway.main[*].id)
}

output "jumpbox_public_ip" {
  value = aws_instance.jumpbox.public_ip
}
