output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

output "nat_gateway_id" {
  value = one(aws_nat_gateway.main[*].id)
}