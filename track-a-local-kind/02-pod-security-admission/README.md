# 02 — Pod Security Admission (PSA)

## ゴール
PSP 廃止後のデフォルト機構である **Pod Security Admission** を、namespace ラベルで適用し、`baseline` / `restricted` の差を観察する。

## やること (予定)
1. namespace に `pod-security.kubernetes.io/enforce=baseline` を貼る
2. `privileged: true` な Pod が拒否されることを確認
3. `restricted` に上げ、`runAsNonRoot` 未指定 Pod が拒否されることを確認
4. `warn` / `audit` モードの違いを比較

## TODO
- [ ] `manifests/ns-baseline.yaml`, `ns-restricted.yaml`
- [ ] 違反 Pod 例 (privileged / root / hostPath)
- [ ] cluster-wide のデフォルトを `AdmissionConfiguration` で設定する例 (`01-cluster-up` の kind config に同居)

## 参考
- https://kubernetes.io/docs/concepts/security/pod-security-admission/
- https://kubernetes.io/docs/concepts/security/pod-security-standards/
- PSP → PSS 対応表: https://kubernetes.io/docs/reference/access-authn-authz/psp-to-pod-security-standards/
