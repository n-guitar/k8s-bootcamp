# 01 — Terraform で VPC + EC2 を構築

## ゴール
control-plane × 1 + worker × 2 の EC2 と、それを置く VPC / Subnet / SG を Terraform で作る。

## やること (予定)
1. `terraform/` 配下に `main.tf` / `variables.tf` / `outputs.tf`
2. VPC (10.0.0.0/16) + Public Subnet × 1〜2 (multi-AZ オプション)
3. SG: 自分の IP からの 22, クラスタ間の 6443/10250/2379-2380/179 (BGP)/30000-32767
4. EC2 (Ubuntu 24.04, t3.medium) × 3 + cloud-init で `containerd`, `kubeadm`, `kubelet`, `kubectl` を install
5. `outputs.tf` で各ノードの Public IP / Private IP

## TODO
- [ ] `terraform/main.tf`
- [ ] `cloud-init/containerd.yaml`
- [ ] tfstate のリモート保管 (S3 + DynamoDB lock) はオプション
- [ ] SSM 経由ログインのドキュメント

## 参考
- AWS Provider: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- containerd install on Ubuntu: https://kubernetes.io/docs/setup/production-environment/container-runtimes/#containerd
