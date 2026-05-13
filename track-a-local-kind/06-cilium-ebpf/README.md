# 06 — Cilium / eBPF

## ゴール
- kind を **kube-proxy 無し** で起動 (`networking.kubeProxyMode: "none"`)
- **Cilium** を CNI として install、kube-proxy replacement を有効化
- **Hubble** で L3/L4/L7 のフローを観察
- `CiliumNetworkPolicy` で L7 (HTTP method) のフィルタリング

## やること (予定)
1. kind を kube-proxy なしで再作成 (この章だけ別クラスタを推奨)
2. `cilium install --version <latest> --set kubeProxyReplacement=true`
3. `cilium hubble enable --ui` → port-forward で UI
4. CNP で `GET /healthz` のみ通す等の L7 ポリシー

## TODO
- [ ] `kind-config-no-kubeproxy.yaml`
- [ ] `manifests/cnp-l7-http.yaml`
- [ ] AdminNetworkPolicy alpha の試行 (オプション)

## 参考
- https://docs.cilium.io/
- Hubble: https://github.com/cilium/hubble
- AdminNetworkPolicy: https://network-policy-api.sigs.k8s.io/
