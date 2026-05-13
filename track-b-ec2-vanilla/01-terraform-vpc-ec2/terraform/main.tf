provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project = "k8s-bootcamp"
      Track   = "B"
      Owner   = var.owner
    }
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_key_pair" "this" {
  key_name   = "k8s-bootcamp"
  public_key = var.ssh_public_key
}
