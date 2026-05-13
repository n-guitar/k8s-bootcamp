locals {
  user_data = templatefile("${path.module}/../cloud-init/node.yaml.tftpl", {
    k8s_version = var.k8s_version
  })
}

resource "aws_instance" "cp" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.node.id]
  key_name                    = aws_key_pair.this.key_name
  associate_public_ip_address = true
  user_data                   = local.user_data

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    tags        = { Name = "k8s-bootcamp-cp-root" }
  }

  tags = {
    Name = "k8s-bootcamp-cp"
    Role = "control-plane"
  }
}

resource "aws_instance" "worker" {
  count                       = var.worker_count
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.node.id]
  key_name                    = aws_key_pair.this.key_name
  associate_public_ip_address = true
  user_data                   = local.user_data

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    tags        = { Name = "k8s-bootcamp-worker-${count.index}-root" }
  }

  tags = {
    Name = "k8s-bootcamp-worker-${count.index}"
    Role = "worker"
  }
}
