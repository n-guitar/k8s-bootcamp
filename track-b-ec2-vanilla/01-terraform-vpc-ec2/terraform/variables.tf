variable "region" {
  type    = string
  default = "us-east-1"
}

variable "owner" {
  type        = string
  description = "Tag value for Owner (e.g. your name)"
}

variable "ssh_public_key" {
  type        = string
  description = "Contents of ~/.ssh/k8s-bootcamp.pub"
}

variable "my_ip_cidr" {
  type        = string
  description = "Your public IP as a /32 CIDR (e.g. 203.0.113.10/32)"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "worker_count" {
  type    = number
  default = 2
}

variable "k8s_version" {
  type        = string
  default     = "1.32"
  description = "kubeadm/kubelet minor version (e.g. 1.32). 05-kubeadm-upgrade で 1.33 に上げる。"
}
