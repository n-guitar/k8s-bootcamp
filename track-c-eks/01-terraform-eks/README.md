# 01 — Terraform で EKS 構築

## ゴール
`terraform-aws-modules/eks/aws` を使って v1.33 の EKS を **Managed Node Group 最小構成** で構築。Pod Security Admission の cluster default を **`baseline`** に。

## やること (予定)
1. `terraform/main.tf` で VPC + EKS module
2. EKS addon: `vpc-cni`, `kube-proxy` (※ Cilium に置き換える場合は無効化), `coredns`, `eks-pod-identity-agent`, `aws-ebs-csi-driver`
3. PSA は `AdmissionConfiguration` を kube-apiserver 引数で指定 (EKS managed config では制約あり → 別途記載)
4. `aws eks update-kubeconfig` で接続
5. `kubectl get nodes` で v1.33 確認

## TODO
- [ ] `terraform/main.tf`
- [ ] OIDC provider 出力 (Pod Identity を使うが IRSA 移行検証で必要)
- [ ] CloudWatch Container Insights は別章 or オプション

## 参考
- terraform-aws-modules/eks: https://github.com/terraform-aws-modules/terraform-aws-eks
- EKS PSA: https://docs.aws.amazon.com/eks/latest/userguide/pod-security-policy-removal-faq.html
