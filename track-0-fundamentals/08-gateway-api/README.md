# 08 — Gateway API でクラスタ外公開

## ゴール
- 外部からクラスタ内アプリへ届ける標準として **Gateway API** を学ぶ
- 3 階層 (GatewayClass / Gateway / HTTPRoute) の責任分離を理解
- 旧来の Ingress との違いを最後に補足 (= 触れる程度で OK)

## やること (予定)
1. Gateway API CRD を install
2. 軽量な実装 (Envoy Gateway や Cilium Gateway) を helm で install
3. `GatewayClass` を確認、`Gateway` (リスナー 80) を作成
4. `HTTPRoute` で host / path ルーティング
5. (発展) HTTPRoute の `backendRefs` weight でカナリア 90:10
6. (補足) Ingress の YAML を 1 つ並べて「歴史」を 5 分で説明

## TODO
- [ ] `manifests/gateway.yaml`, `httproute.yaml`
- [ ] kind extraPortMappings との対応図
- [ ] Track A 04 章 (深掘り) への接続

## 参考
- Gateway API: https://gateway-api.sigs.k8s.io/
- なぜ Ingress でなく Gateway API か: https://gateway-api.sigs.k8s.io/concepts/api-overview/
