# 00 — Prerequisites (Track B)

## 必要なもの
- AWS アカウント (sandbox 推奨)
- AWS CLI v2 (`aws sts get-caller-identity` が通る状態)
- Terraform v1.7+
- SSH 鍵 (Session Manager を使うなら省略可)
- 予算アラート (CloudWatch Billing alarm) を **必ず先に** 設定

## TODO
- [ ] IAM ユーザ / Role の最小権限例
- [ ] `aws configure` または SSO 設定
- [ ] バージョン確認スクリプト
