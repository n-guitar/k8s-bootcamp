# 08 — Gateway API でクラスタ外公開

## ゴール
- 外部からクラスタ内アプリへ届ける標準として **Gateway API** を学ぶ
- 3 階層 (`GatewayClass` / `Gateway` / `HTTPRoute`) の責任分離を理解
- 旧来の `Ingress` との違いを最後に補足 (= 触れる程度で OK)

---

## 🤔 なぜ必要？ (ストーリー)

> ある日、上司:「`/api` は新サービスに、`/legacy` は旧サービスに、`/static` は CDN フォールバックに振りたい」
>
> あなたは Ingress を 1 つ作った。
> → うまく動かない。`nginx.ingress.kubernetes.io/rewrite-target` を付ける必要があった。
> → 別のクラスタは Traefik で、同じ書き方が **効かない**。
> → カナリアしたい? `nginx.ingress.kubernetes.io/canary-weight: "10"` ベンダ独自アノテーション。
> → mTLS したい? また別のアノテーション。
>
> 「**ベンダごとに違うアノテーションを覚えるのが本業じゃない**」
>
> しかも、Ingress を書く人 / Gateway を運用する人 / クラスタを作る人は **別チーム** のことが多い。
> でも Ingress は **1 つの YAML に全部詰め込む** 仕様。誰の責任なのかが曖昧。
>
> これらの問題に対する CNCF の答えが **Gateway API** (v1.0 GA, 2023/10) です。

## ✨ 面白いポイント (設計)

### 1. **責任分離 3 階層**

```
GatewayClass    (インフラ屋)   ← どの実装か (Envoy / Cilium / NGINX Gateway / ALB)
   ↑
Gateway         (クラスタ管理者) ← リスナー、TLS、外部 IP の確保
   ↑
HTTPRoute       (アプリ屋)     ← パス・ホスト・カナリア
```

> **痺れ所:** 「**書ける人が違うものは、リソースを分ける**」。
> アプリ屋は HTTPRoute だけ書けばよく、Gateway や GatewayClass の知識は要らない。
> 逆に管理者は HTTPRoute を細かく見なくていい。**RBAC で綺麗に切れる**。

### 2. **`backendRefs` で重み付けカナリアが標準**

```yaml
backendRefs:
  - name: web-v1
    port: 80
    weight: 90
  - name: web-v2
    port: 80
    weight: 10
```

ベンダ独自アノテーション無し、**Gateway API 標準**。
Cilium Gateway / Envoy Gateway / Istio / NGINX Gateway Fabric / ALB Controller、どれでも同じ書き方。

### 3. **HTTPRoute / GRPCRoute / TCPRoute / TLSRoute / TLSRoute / UDPRoute**

L4 / L7 / gRPC それぞれに **型** がある。Ingress (L7 HTTP のみ) の限界を超えた。

### 4. **Service Mesh との統一 (GAMMA)**

同じ HTTPRoute が **クラスタ外公開** と **mesh 内ルーティング** の **両方** で使える。
Istio Ambient や Cilium Service Mesh が、同じリソースで mesh ルートを書ける。

> **痺れ所:** Ingress (北南トラフィック) と Service Mesh (東西トラフィック) を **同じ語彙** で扱える。

## 😱 あるある罠

- **実装を入れずに HTTPRoute だけ書く**: Gateway API は CRD だけ入れても **何も起きない**。Envoy Gateway / Cilium Gateway 等の **実装** を入れて初めて動く
- **`parentRefs` の指定漏れ**: HTTPRoute は **どの Gateway に紐づくか** を `parentRefs` で書く。書き忘れて「届かない」事故が多い
- **kind の port mapping を忘れる**: kind 上で host から到達するには `extraPortMappings` で 80/443 を抜く必要 (02 章で抜いてある想定)
- **Ingress 資産が大量に残っている**: Gateway API への移行は **段階的** に。Ingress も並存可

## やること

> このトラックでは軽量で kind と相性の良い **Envoy Gateway** を使います (Cilium Gateway は Track A 06 で扱う)。

### 0. 準備

```bash
kubectl create ns ch08
kubectl label ns ch08 pod-security.kubernetes.io/enforce=baseline --overwrite
```

### 1. Gateway API CRD と Envoy Gateway を入れる

**最短手順**:
```bash
../scripts/install-gateway.sh
```

中身は以下と等価です (時間があれば手で打ってもよい):
```bash
# Gateway API CRD
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml

# Envoy Gateway
helm install eg oci://docker.io/envoyproxy/gateway-helm \
  --version v1.1.0 -n envoy-gateway-system --create-namespace
kubectl -n envoy-gateway-system wait --for=condition=Ready pods --all --timeout=180s
```

### 2. アプリ 2 つを立てる (v1 / v2 でカナリアの素材)

```yaml
# apps.yaml
apiVersion: apps/v1
kind: Deployment
metadata: {name: web-v1, namespace: ch08}
spec:
  replicas: 2
  selector: {matchLabels: {app: web, version: v1}}
  template:
    metadata: {labels: {app: web, version: v1}}
    spec:
      containers:
        - name: nginx
          image: nginxdemos/hello:plain-text
          ports: [{containerPort: 80}]
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: web-v2, namespace: ch08}
spec:
  replicas: 2
  selector: {matchLabels: {app: web, version: v2}}
  template:
    metadata: {labels: {app: web, version: v2}}
    spec:
      containers:
        - name: nginx
          image: hashicorp/http-echo:1.0.0
          args: ["-text=hello from v2", "-listen=:80"]
          ports: [{containerPort: 80}]
---
apiVersion: v1
kind: Service
metadata: {name: web-v1, namespace: ch08}
spec:
  selector: {app: web, version: v1}
  ports: [{port: 80, targetPort: 80}]
---
apiVersion: v1
kind: Service
metadata: {name: web-v2, namespace: ch08}
spec:
  selector: {app: web, version: v2}
  ports: [{port: 80, targetPort: 80}]
```

```bash
kubectl apply -f apps.yaml
```

### 3. Gateway を立てる

```yaml
# gateway.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata: {name: eg}
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: shared
  namespace: ch08
spec:
  gatewayClassName: eg
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces: {from: Same}
```

```bash
kubectl apply -f gateway.yaml
kubectl -n ch08 get gateway shared
```

### 4. HTTPRoute (= アプリ屋の領域)

最初は v1 だけにすべてを流す:

```yaml
# httproute.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: web
  namespace: ch08
spec:
  parentRefs:
    - name: shared
  hostnames: ["app.local"]
  rules:
    - matches:
        - path: {type: PathPrefix, value: /}
      backendRefs:
        - name: web-v1
          port: 80
```

```bash
kubectl apply -f httproute.yaml
kubectl -n ch08 get httproute web
```

### 5. host から叩く

kind の `extraPortMappings: 80→80` がある想定 (02 章設定)。

```bash
curl -s -H 'Host: app.local' http://localhost/ | head -3
# → web-v1 が応答
```

> Mac で `app.local` を Host ヘッダ無しで叩きたいなら `/etc/hosts` に `127.0.0.1 app.local` を追加。

### 6. カナリア 90:10

```yaml
# httproute-canary.yaml (rules を書き換え)
rules:
  - matches: [{path: {type: PathPrefix, value: /}}]
    backendRefs:
      - {name: web-v1, port: 80, weight: 90}
      - {name: web-v2, port: 80, weight: 10}
```

```bash
kubectl apply -f httproute-canary.yaml
for i in $(seq 1 20); do
  curl -s -H 'Host: app.local' http://localhost/
done | sort | uniq -c
# → 約 18:2 で v1/v2 が分かれる
```

### 7. Ingress との対応 (5 分補足)

| 機能 | Ingress | Gateway API |
|---|---|---|
| 入り口リソース | `Ingress` (1 個に全部) | `GatewayClass` + `Gateway` + `*Route` |
| カナリア | ベンダ独自 annotation | `backendRefs[].weight` 標準 |
| L4 / gRPC | 不可 / 限定的 | `TCPRoute` / `GRPCRoute` |
| ロール分離 | 不明確 | リソース粒度で明確 |
| Service Mesh 連携 | 別物 | GAMMA で統一 |

### 8. 後片付け

```bash
kubectl delete -f httproute.yaml || true
kubectl delete -f gateway.yaml
kubectl delete ns ch08
helm -n envoy-gateway-system uninstall eg
```

## やってみて気づくこと

- アプリ屋が触るのは **HTTPRoute だけ**。Gateway は管理者の領域、と分かれている快適さ
- カナリアが **標準仕様** に入っている安心感 (ベンダロックインなし)
- `parentRefs` でリソース間が **明示的に繋がる** ので、Ingress より追跡しやすい

## 参考

- Gateway API: https://gateway-api.sigs.k8s.io/
- Envoy Gateway: https://gateway.envoyproxy.io/
- GAMMA initiative: https://gateway-api.sigs.k8s.io/concepts/gamma/
- Ingress との比較: https://kubernetes.io/blog/2023/10/31/gateway-api-ga/
