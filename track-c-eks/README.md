# Track C — EKS + モダン運用スタック

マネージド (EKS) を前提に、**Karpenter / AWS Load Balancer Controller + Gateway API / EKS Pod Identity / EBS-EFS CSI / Argo CD / cosign + Kyverno** を一通り組み上げるトラックです。

> **注意:** Track B 以上に課金が発生します (EKS control-plane 自体に $0.10/h)。
> 各章の検証が終わるたびに `99-cleanup` の方針で寝かさず、最終日は **必ず destroy**。

## 章一覧

| # | ディレクトリ | 内容 |
|---|---|---|
| 00 | [00-prereqs](./00-prereqs/) | AWS CLI / Terraform / eksctl (option) / kubectl |
| 01 | [01-terraform-eks](./01-terraform-eks/) | `terraform-aws-modules/eks/aws` で EKS 構築、PSA 適用 |
| 02 | [02-karpenter](./02-karpenter/) | Karpenter で Node オートスケール (CA は使わない) |
| 03 | [03-alb-gateway-api](./03-alb-gateway-api/) | AWS Load Balancer Controller + Gateway API |
| 04 | [04-pod-identity](./04-pod-identity/) | IRSA → EKS Pod Identity への移行 |
| 05 | [05-csi-ebs-efs](./05-csi-ebs-efs/) | EBS / EFS CSI driver |
| 06 | [06-argo-cd](./06-argo-cd/) | Argo CD で GitOps |
| 07 | [07-supply-chain](./07-supply-chain/) | cosign sign on ECR + Kyverno verifyImages |
| 99 | [99-cleanup](./99-cleanup/) | `terraform destroy` 等 |

## クラスタ構成イメージ

```
EKS Cluster (v1.33)
 ├─ Managed Node Group  (system / system-critical 用、最小)
 ├─ Karpenter           (アプリ用 Node を動的に launch)
 ├─ AWS LB Controller   (ALB / NLB / Gateway API)
 ├─ EKS Pod Identity Agent
 ├─ EBS / EFS CSI       (managed addon)
 ├─ Argo CD (argocd ns)
 └─ Kyverno + verifyImages policy
```

## 想定コスト

- EKS control plane: $0.10/h ≒ $2.4/日
- Worker (t3.medium × 2, Spot 50%): 約 $0.5〜1/日
- ALB / NLB: それぞれ ~$0.025/h + LCU 課金
- 学習中は **`terraform destroy` を毎晩** が安全

## 共通方針

- IaC は **Terraform**、helm 物は **helm provider** か **kustomize ApplicationSet (Argo CD)** に寄せる
- IAM 連携は **IRSA より EKS Pod Identity を優先** (新しいワークロード前提)
- LB は **Gateway API + ALB Controller** をデフォルトに、Ingress は最小限
