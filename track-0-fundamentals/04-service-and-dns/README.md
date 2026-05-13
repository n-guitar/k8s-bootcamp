# 04 — Service と DNS

## ゴール
- なぜ Pod IP を直接使わないのか (= 揮発性)
- **Service** 4 タイプ (ClusterIP / NodePort / LoadBalancer / ExternalName) の使い分け
- クラスタ内 DNS (`<svc>.<ns>.svc.cluster.local`)
- `headless Service` (`clusterIP: None`) と StatefulSet 系の話に触れる

## やること (予定)
1. Deployment + ClusterIP Service を作って Pod 間で名前解決
2. `nslookup` Pod を立てて DNS レコードを確認
3. NodePort で host から到達
4. (option) MetalLB か cloud-provider-kind で LoadBalancer を体験
5. `kube-proxy` の役割と、Track A 06 章 (Cilium で置き換え) への伏線

## TODO
- [ ] `manifests/service-clusterip.yaml` 他
- [ ] DNS パターンの一覧表
- [ ] EndpointSlice の説明 (旧 Endpoints は v1.33 で残存だが新規は Slice 推奨)

## 参考
- Service: https://kubernetes.io/docs/concepts/services-networking/service/
- DNS for Services: https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/
