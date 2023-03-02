output "cluster_name" {
  value = var.cluster_name
}

output "elb_dns_name" {
  value = aws_lb.cluster-api.dns_name
}

output "jumpbox_public_ip" {
  value = module.vpc.jumpbox_public_ip
}

output "controller_nodes" {
  value = <<EOT
%{ for controller in module.cluster.controller_nodes ~}
${controller.private_ip}
%{ endfor ~}
EOT
}

output "worker_nodes" {
  value = <<EOT
%{ for worker in module.cluster.worker_nodes ~}
${worker.private_ip}
%{ endfor ~}
EOT
}