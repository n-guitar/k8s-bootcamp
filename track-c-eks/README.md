# Track C — EKS + モダン運用スタック

マネージド (EKS) を前提に、**Karpenter / AWS Load Balancer Controller + Gateway API / EKS Pod Identity / EBS-EFS CSI / Argo CD / cosign + Kyverno** を一通り組み上げるトラックです。

## 🤔 なぜ Track C をやるのか

> **ストーリー:** Track B で素の k8s を 1 度組み立てた。中身は分かった。でも本番で毎晩 etcd の面倒を見たくはない。
> 「**面倒な所はクラウドに任せ、面白い所だけ自分で書く**」のがマネージドの本懐。Track C はその境界線を学ぶ場所です。

- 何が EKS にお任せで、何が自分の責任か (Shared Responsibility) を 1 つずつ確認
- IRSA → **EKS Pod Identity** という「もう Trust Policy 書かなくていい」進化
- Cluster Autoscaler → **Karpenter** という「Node 種を Pending Pod から逆算」の発想

## ✨ Track C でとくに痺れて欲しい設計

- **Karpenter**: 「先に ASG を作る」のではなく、「**Pending Pod を見てから最適な EC2 を launch**」する逆転の発想。起動 15〜60 秒
- **Pod Identity Agent**: Node 上の小さなエージェントが SDK のクレデンシャルを差し込む。IRSA より遥かに単純
- **Gateway API on ALB**: ALB Controller が `Gateway` CR を読んで ALB を生やす。Ingress アノテーションの闇から解放

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
