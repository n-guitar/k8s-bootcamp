# 99 — Cleanup (Track C)

## ゴール
**EKS control plane と ALB/NLB の課金停止**。tag ベースで残骸を全 region 検索。

## やること
1. Argo CD で管理している `Application` を全削除 (依存 LB を先に消す)
2. `kubectl delete svc --all -A` → ALB / NLB の取りこぼし防止
3. PVC を delete (EBS / EFS の残)
4. `terraform destroy`
5. Cost Explorer で残コストを確認、不要なら ECR repo / S3 (tfstate) / Route53 record も整理

## TODO
- [ ] cleanup チェックリスト
- [ ] CloudWatch Log Group 残骸の削除手順
- [ ] `aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=k8s-bootcamp`
