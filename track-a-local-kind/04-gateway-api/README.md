# 04 — Gateway API

## ゴール
Ingress の後継である **Gateway API** (v1.0 GA, 2023/10) を、ローカル kind で動かす。

## やること (予定)
1. Gateway API の CRD を install
2. **Envoy Gateway** または **Cilium Gateway** を導入 (Cilium 章 06 と統合してもよい)
3. `GatewayClass` / `Gateway` / `HTTPRoute` を 3 階層で作る
4. host ヘッダ・パスでルーティングを試す
5. (発展) `HTTPRoute` の weight でカナリア

## TODO
- [ ] `manifests/gatewayclass.yaml`, `gateway.yaml`, `httproute-canary.yaml`
- [ ] kind extraPortMappings との対応図
- [ ] Ingress との対応表

## 参考
- https://gateway-api.sigs.k8s.io/
- Envoy Gateway: https://gateway.envoyproxy.io/
- Cilium Gateway: https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/
