# 03 — AWS Load Balancer Controller + Gateway API

## ゴール
ALB Controller の **Gateway API サポート** (2024 以降) を使い、`Ingress` ではなく `Gateway` / `HTTPRoute` で ALB を制御する。

## やること (予定)
1. AWS Load Balancer Controller を helm install (Pod Identity)
2. Gateway API CRD を install
3. `GatewayClass` (`controllerName: gateway.k8s.aws/alb`)
4. `Gateway` + `HTTPRoute` 作成 → ALB が自動生成
5. (発展) 重み付きカナリアを HTTPRoute で

## TODO
- [ ] `manifests/gatewayclass-alb.yaml`
- [ ] cert-manager + ACM どちらで TLS 終端するか比較
- [ ] NLB (Service type=LoadBalancer) 構成も別途用意するか検討

## 参考
- AWS LB Controller: https://kubernetes-sigs.github.io/aws-load-balancer-controller/
- Gateway API on ALB: https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/gateway/gateway-api/
