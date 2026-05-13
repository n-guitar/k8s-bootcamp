# 04 — EKS Pod Identity (IRSA からの移行)

## ゴール
- 旧来の **IRSA** (OIDC + ServiceAccount annotation) を確認
- 2023/11 GA の **EKS Pod Identity** (Pod Identity Agent + Association) に置き換え
- 違い (信頼ポリシー不要、cross-account 容易) を体感

## やること (予定)
1. IRSA で SA → IAM Role を 1 つ作成し動作確認
2. 同じ SA に対して `aws eks create-pod-identity-association` を Terraform で作成
3. IRSA annotation を外し、Pod Identity だけで権限が効くこと確認
4. SDK 側の Credential Provider Chain 順序確認

## TODO
- [ ] Terraform で Pod Identity Association
- [ ] 並存時の優先度説明
- [ ] STS 周りの観察 (`aws sts get-caller-identity` を Pod 内から)

## 参考
- Pod Identity: https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html
- IRSA との比較: https://aws.amazon.com/jp/blogs/containers/amazon-eks-pod-identity-a-new-way-for-applications-on-eks-to-obtain-iam-credentials/
