# 07 — Supply Chain on EKS (cosign + Kyverno)

## ゴール
- ECR にイメージを push し **cosign で署名** (keyless OIDC または KMS)
- **Kyverno verifyImages** で署名検証を admission に組み込む
- SBOM (`cosign attach sbom`) と SLSA provenance も体験

## やること (予定)
1. ECR repo を Terraform で作成
2. GitHub Actions で build → push → `cosign sign` (OIDC keyless 推奨)
3. EKS に Kyverno install
4. `verifyImages` policy で ECR の特定 path のみ署名検証
5. (発展) `cosign verify-attestation` で SLSA provenance を要求

## TODO
- [ ] GitHub Actions workflow サンプル
- [ ] Kyverno policy YAML
- [ ] OIDC trust の設定 (AWS IAM OIDC + GitHub)

## 参考
- Sigstore: https://www.sigstore.dev/
- Kyverno verifyImages: https://kyverno.io/policies/?policytypes=verifyImages
- AWS Signer for container images: https://docs.aws.amazon.com/signer/latest/developerguide/Welcome.html
