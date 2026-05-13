# 06 — Argo CD on EKS

## ゴール
このリポジトリ (fork でも可) を Argo CD で sync させ、**App-of-Apps** で全アドオン (LB Controller / Karpenter / Kyverno) を Argo CD 配下に置く。

## やること (予定)
1. Argo CD を Terraform / helm で install
2. ALB Gateway 経由で UI を公開 (TLS は ACM)
3. `ApplicationSet` で複数 namespace へ
4. Sync wave で `CRD → 設定 → Workload` の順序保証
5. (発展) Notifications で Slack 通知

## TODO
- [ ] `manifests/argocd-bootstrap.yaml`
- [ ] sync wave サンプル
- [ ] Argo CD 自身を Argo CD で管理する (self-management)

## 参考
- https://argo-cd.readthedocs.io/
- App-of-Apps: https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/
