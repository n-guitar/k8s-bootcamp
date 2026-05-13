# 08 — GitOps with Argo CD

## ゴール
Argo CD を導入し、本リポジトリ (または fork) の `manifests/` を **GitOps で自動同期** する。

## やること (予定)
1. Argo CD を `argocd` namespace に install (manifest or helm)
2. `argocd-cmd-params-cm` で `server.insecure=true` (ローカル限定)
3. `Application` CR を 1 つ作って HTTPRoute 等を sync
4. `ApplicationSet` で複数 namespace に展開
5. App-of-apps パターン体験

## TODO
- [ ] `manifests/argocd-install.yaml` (kustomize で patch)
- [ ] `manifests/apps/root.yaml` (app-of-apps)
- [ ] sync wave / hooks の例

## 参考
- https://argo-cd.readthedocs.io/
- ApplicationSet: https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/
