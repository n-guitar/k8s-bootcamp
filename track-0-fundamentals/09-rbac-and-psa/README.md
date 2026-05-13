# 09 — RBAC と Pod Security Admission

## ゴール
- 「人 / ServiceAccount → Role → 操作」の RBAC モデル
- ServiceAccount トークンが v1.24 以降 **projected volume / expiring** がデフォルトになったこと
- 旧 PSP は無く、**Pod Security Admission (PSA)** で namespace 単位にプロファイル適用が標準

## やること (予定)
1. 自分用 ServiceAccount を作って `kubectl auth can-i` で何が出来るか確認
2. Role / RoleBinding で「特定 namespace の Pod を get/list」だけ許可
3. ClusterRole / ClusterRoleBinding で横断権限の例
4. namespace に `pod-security.kubernetes.io/enforce=baseline` を貼って、privileged Pod が拒否されることを確認
5. `restricted` プロファイルに上げて、`runAsNonRoot` 未指定 Pod が拒否されることを確認

## TODO
- [ ] `manifests/role.yaml`, `rolebinding.yaml`
- [ ] `kubectl create token` で短命トークンを発行する手順
- [ ] PSA の `warn` / `audit` / `enforce` の使い分け表

## 参考
- RBAC: https://kubernetes.io/docs/reference/access-authn-authz/rbac/
- PSA: https://kubernetes.io/docs/concepts/security/pod-security-admission/
- SA Token 仕様変更: https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/#bound-service-account-tokens
