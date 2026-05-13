resource "aws_security_group" "node" {
  name        = "k8s-bootcamp-node"
  description = "Kubernetes nodes (control-plane + worker)"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "k8s-bootcamp-node" }
}

# --- ingress ---
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.node.id
  description       = "SSH from my IP"
  cidr_ipv4         = var.my_ip_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "api_from_me" {
  security_group_id = aws_security_group.node.id
  description       = "kube-apiserver from my IP"
  cidr_ipv4         = var.my_ip_cidr
  ip_protocol       = "tcp"
  from_port         = 6443
  to_port           = 6443
}

# Node-to-Node 全許可 (学習用)
resource "aws_vpc_security_group_ingress_rule" "self_all" {
  security_group_id            = aws_security_group.node.id
  description                  = "all traffic between nodes"
  referenced_security_group_id = aws_security_group.node.id
  ip_protocol                  = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "nodeport" {
  security_group_id = aws_security_group.node.id
  description       = "NodePort range from my IP"
  cidr_ipv4         = var.my_ip_cidr
  ip_protocol       = "tcp"
  from_port         = 30000
  to_port           = 32767
}

# --- egress ---
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.node.id
  description       = "egress all"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
