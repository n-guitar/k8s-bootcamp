# 09 — Supply Chain (cosign + Kyverno verifyImages)

## ゴール
- **cosign** でローカルイメージに署名 (keyless / 鍵モード両方)
- **Kyverno** の `verifyImages` ポリシーで、未署名イメージを admission で拒否

## やること (予定)
1. ローカルレジストリ (kind-registry) を立てる
2. シンプルな nginx イメージを push し、`cosign sign` で署名
3. Kyverno を install (PSA `baseline` namespace に置けるか確認)
4. `verifyImages` ポリシー作成 → 未署名 Pod を拒否、署名済を許可
5. (発展) SBOM を `cosign attach sbom` で添付、`cosign verify-attestation`

## TODO
- [ ] `manifests/kyverno-verify-images.yaml`
- [ ] cosign keyless (OIDC) 注意点 (ローカルだと制限あり、鍵モード推奨)

## 参考
- cosign: https://docs.sigstore.dev/cosign/overview/
- Kyverno verifyImages: https://kyverno.io/policies/?policytypes=verifyImages
- SLSA: https://slsa.dev/
