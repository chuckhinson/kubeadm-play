output "elb_dns_name" {
  value = aws_lb.cluster-api.dns_name
}

output "jumpbox_public_ip" {
  value = module.vpc.jumpbox_public_ip
}
