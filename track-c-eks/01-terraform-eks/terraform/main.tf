# Track C / 01: EKS v1.33 を 1 ファイルで立てるための最小構成
# 章 README と合わせて参照。実運用では versions/vpc/eks/outputs に分割推奨。

terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.70" }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project = "k8s-bootcamp"
      Track   = "C"
      Owner   = var.owner
    }
  }
}

variable "region" { default = "ap-northeast-1" }
variable "owner"  { default = "your-name" }
variable "cluster_name" { default = "bootcamp" }

############################################
# VPC
############################################
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = var.cluster_name
  cidr = "10.20.0.0/16"

  azs             = ["${var.region}a", "${var.region}c", "${var.region}d"]
  private_subnets = ["10.20.1.0/24", "10.20.2.0/24", "10.20.3.0/24"]
  public_subnets  = ["10.20.101.0/24", "10.20.102.0/24", "10.20.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true # 学習用: NAT GW を 1 個に絞ってコスト削減

  public_subnet_tags  = { "kubernetes.io/role/elb"          = 1 }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 }
}

############################################
# EKS
############################################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.24"

  cluster_name    = var.cluster_name
  cluster_version = "1.33"

  cluster_endpoint_public_access = true # 学習用、本番は private + bastion

  # Access Entries モード。実行ユーザを自動で cluster-admin にする
  authentication_mode                       = "API"
  enable_cluster_creator_admin_permissions  = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # 旧来 IRSA との互換のため OIDC provider も出しておく
  enable_irsa = true

  cluster_addons = {
    vpc-cni                = { most_recent = true }
    kube-proxy             = { most_recent = true }
    coredns                = { most_recent = true }
    eks-pod-identity-agent = { most_recent = true }
    aws-ebs-csi-driver     = { most_recent = true }
  }

  eks_managed_node_groups = {
    system = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"
      min_size       = 2
      max_size       = 3
      desired_size   = 2
      labels         = { role = "system" }
    }
  }
}

############################################
# Outputs
############################################
output "cluster_name"           { value = module.eks.cluster_name }
output "cluster_endpoint"       { value = module.eks.cluster_endpoint }
output "oidc_provider_arn"      { value = module.eks.oidc_provider_arn }
output "cluster_security_group" { value = module.eks.cluster_security_group_id }
output "vpc_id"                 { value = module.vpc.vpc_id }
output "private_subnets"        { value = module.vpc.private_subnets }
