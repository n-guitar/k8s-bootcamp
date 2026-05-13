# 00 — Prerequisites (Track C)

## 必要なもの
- AWS アカウント (sandbox 推奨、予算アラート必須)
- AWS CLI v2
- Terraform v1.7+
- kubectl v1.33.x
- helm v3.14+
- (任意) eksctl — Terraform で構築するので必須ではない

## TODO
- [ ] IAM 最小権限案 (`AdministratorAccess` で短時間 / 必要権限の絞り込み案)
- [ ] `aws sso login` 想定の手順
- [ ] kubeconfig 切替の運用 (`aws eks update-kubeconfig --alias bootcamp`)
