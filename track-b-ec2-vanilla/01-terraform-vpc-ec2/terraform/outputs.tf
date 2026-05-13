output "cp_public_ip" {
  value = aws_instance.cp.public_ip
}

output "cp_private_ip" {
  value = aws_instance.cp.private_ip
}

output "worker_public_ips" {
  value = aws_instance.worker[*].public_ip
}

output "worker_private_ips" {
  value = aws_instance.worker[*].private_ip
}

output "ssh_cp" {
  value = "ssh -i ~/.ssh/k8s-bootcamp ubuntu@${aws_instance.cp.public_ip}"
}

output "ssh_workers" {
  value = [for ip in aws_instance.worker[*].public_ip : "ssh -i ~/.ssh/k8s-bootcamp ubuntu@${ip}"]
}
