output "private_subnet_id" {
  value = aws_subnet.private.id
}

output "controller_nodes" {
  value = aws_instance.controllers
}

output "worker_nodes" {
  value = aws_instance.workers
}