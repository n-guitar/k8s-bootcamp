# 05 — ValidatingAdmissionPolicy (CEL)

## ゴール
v1.30 GA の **ValidatingAdmissionPolicy** で、Webhook なしのアドミッションを書く。Kyverno / OPA Gatekeeper と比較。

## やること (予定)
1. `replicas <= 5` 制限の VAP を書く
2. `ValidatingAdmissionPolicyBinding` で対象 namespace を指定
3. CEL で複数フィールドを参照する例
4. 同等を Kyverno で書いた場合との差 (mutation 可否、Webhook 起動順問題など) を比較

## TODO
- [ ] `manifests/vap-replicas-max.yaml`
- [ ] `manifests/vap-image-registry.yaml` (registry.k8s.io 縛り)
- [ ] Kyverno 比較メモ

## 参考
- https://kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy/
- CEL 仕様: https://github.com/google/cel-spec
- KEP-3488: https://github.com/kubernetes/enhancements/tree/master/keps/sig-api-machinery/3488-cel-admission-control
