# 02 — Karpenter

## ゴール
Cluster Autoscaler の代わりに **Karpenter** で Node を動的に launch。Spot 混在最適化、起動時間の速さを体感。

## やること (予定)
1. Karpenter 用 IAM Role (Pod Identity association)
2. helm で karpenter install
3. `EC2NodeClass` / `NodePool` を作成 (AMI: AL2023, Spot+OnDemand 混在)
4. 大量 Pod を `kubectl scale` で投げる → Node が 15〜60 秒で起動するのを観察
5. アイドル時間で Node が自動 deprovision されることを確認

## TODO
- [ ] `manifests/karpenter-nodepool.yaml`
- [ ] EC2 Fleet 関連 IAM
- [ ] Disruption budget (`disruption.budgets`) の例

## 参考
- https://karpenter.sh/
- EKS Best Practices (Karpenter): https://aws.github.io/aws-eks-best-practices/karpenter/
