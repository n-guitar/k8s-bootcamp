# 04 — Gateway API (深掘り編)

## ゴール
- Track 0 ch08 で触れた Gateway API を **より深く** 体験する
- **HTTPRoute `backendRefs[].weight`** でカナリアを操作
- **GRPCRoute** で gRPC を Ingress アノテーション無しに routing
- **ReferenceGrant** で **cross-namespace** backend を許可する仕組みを理解
- **GAMMA** (Gateway API for Service Mesh) の概要を押さえる

> 前提: 01 章のクラスタが起動済み。Track 0 ch08 を一度通っていると話が早いです (が、必須ではない)。

---

## 🤔 なぜ必要？ (ストーリー)

> あなたは前職で Ingress を書いていた。
> 「カナリアしたい?」→ `nginx.ingress.kubernetes.io/canary-weight: "10"`
> 「rewrite したい?」→ `nginx.ingress.kubernetes.io/rewrite-target: /$2`
> 「mTLS したい?」→ `nginx.ingress.kubernetes.io/auth-tls-...`
> 「gRPC したい?」→ `nginx.ingress.kubernetes.io/backend-protocol: "GRPC"`
>
> 別のチームは Traefik、別のクラスタは ALB。同じ要件でも **アノテーション名がぜんぶ違う**。
> 「**ベンダごとに違うアノテーションを覚えるのが本業じゃない**」
>
> しかも Ingress は **1 つの YAML に "外部 IP・TLS・ルーティング" を全部詰める** 仕様。
> インフラ屋・クラスタ管理者・アプリ屋で **責任分界点が曖昧**。GitOps で誰がどこを触っていいかわからない。
>
> CNCF の答えが **Gateway API** (v1.0 GA, 2023/10)。Ingress 時代の "アノテーション地獄" からの解放、それが本章の主題。

## ✨ 面白いポイント (設計)

### 1. **責任分離 3 階層 (おさらい)**

```
GatewayClass    (インフラ屋)   ← どの実装か (Envoy / Cilium / NGINX Gateway / ALB)
   ↑
Gateway         (クラスタ管理者) ← リスナー、TLS、外部 IP の確保
   ↑
HTTPRoute       (アプリ屋)     ← パス・ホスト・カナリア
GRPCRoute / TLSRoute / TCPRoute / UDPRoute  ← 用途別の型
```

### 2. **`backendRefs[].weight` が標準仕様**

ベンダ独自アノテーション無し。**Gateway API 標準** のカナリア:

```yaml
backendRefs:
  - {name: web-v1, port: 80, weight: 90}
  - {name: web-v2, port: 80, weight: 10}
```

Envoy Gateway / Cilium Gateway / Istio / NGINX Gateway Fabric / ALB Controller、全部 **同じ書き方**。

> **痺れ所:** "**カナリアのような共通要件は仕様に入れる**"。ベンダロックインから解放され、移行コストが激減。

### 3. **`*Route` が L4 / L7 / gRPC で分かれている**

| Route | プロトコル | 状況 |
|---|---|---|
| `HTTPRoute` | HTTP/1.1, HTTP/2 | GA (v1.0) |
| `GRPCRoute` | gRPC | GA (v1.1) |
| `TLSRoute` | TLS passthrough (SNI) | experimental |
| `TCPRoute` / `UDPRoute` | L4 | experimental |

Ingress (L7 HTTP only) の限界をきれいに超えた設計。

### 4. **`ReferenceGrant` = cross-namespace 参照の許可状**

別 namespace の Service / Secret を backend にしたい時、Gateway API は **デフォルトで拒否**。
許可するには **被参照側** の ns に `ReferenceGrant` を置く:

```yaml
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata: {name: allow-from-gw, namespace: backend-ns}
spec:
  from:
    - group: gateway.networking.k8s.io
      kind:  HTTPRoute
      namespace: gw-ns
  to:
    - group: ""
      kind:  Service
```

> **痺れ所:** Ingress は "他 ns の Service を参照する" 仕様が無かった。Gateway API は **明示的な許可** モデルで cross-namespace を解禁。SOC 監査の説明が **格段に楽**。

### 5. **GAMMA — mesh と統一**

GAMMA (Gateway API for Mesh) は、**同じ HTTPRoute を mesh 内 routing にも使う** initiative。
HTTPRoute の `parentRefs` に `kind: Gateway` ではなく `kind: Service` を書くと、**東西トラフィック** のルートに。

```yaml
parentRefs:
  - group: ""
    kind: Service
    name: web      # ← Gateway ではなく Service
```

> **痺れ所:** **Ingress (北南) と Service Mesh (東西) を同じ語彙** で扱える。Istio Ambient や Cilium Service Mesh はこのモデルを採用。

## 😱 あるある罠

- **CRD だけ入れて動かない**: Gateway API は仕様 (CRD)。**実装** (Envoy Gateway / Cilium Gateway / NGINX Gateway Fabric / Istio) を入れて初めて動く
- **`parentRefs` 書き忘れ**: HTTPRoute が **どの Gateway に紐づくか** を書き忘れて "繋がらない" 事故
- **`allowedRoutes` の絞り過ぎ**: Gateway 側で `namespaces: {from: Same}` にしていて、別 ns の Route が attach できない
- **kind の port mapping を忘れる**: host の 80/443 を抜いていないと `curl http://localhost` が届かない (01 章で抜いている前提)
- **cross-namespace でハマる**: `ReferenceGrant` の方向を逆に書きがち (= **参照される側に置く**)
- **GRPCRoute の port mismatch**: gRPC は HTTP/2 over TLS が多い。listener が HTTPS でないと届かない事故

## やること

このトラックでは Envoy Gateway を使います (Cilium Gateway は 06 章で扱う)。Track 0 ch08 と同じ実装なので、CRD と controller のインストールはおさらいから。

### 0. 準備

```bash
kubectl create ns ch04-gw
kubectl label ns ch04-gw pod-security.kubernetes.io/enforce=baseline --overwrite

kubectl create ns ch04-backend
kubectl label ns ch04-backend pod-security.kubernetes.io/enforce=baseline --overwrite
```

### 1. Gateway API CRD と Envoy Gateway を入れる

```bash
# Gateway API standard CRD (HTTPRoute / GRPCRoute GA 対応)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml

# Envoy Gateway
helm install eg oci://docker.io/envoyproxy/gateway-helm \
  --version v1.1.0 \
  -n envoy-gateway-system --create-namespace
kubectl -n envoy-gateway-system wait --for=condition=Ready pods --all --timeout=180s
```

### 2. v1 / v2 アプリと Gateway

```yaml
# apps.yaml
apiVersion: apps/v1
kind: Deployment
metadata: {name: web-v1, namespace: ch04-gw}
spec:
  replicas: 2
  selector: {matchLabels: {app: web, version: v1}}
  template:
    metadata: {labels: {app: web, version: v1}}
    spec:
      containers:
        - name: app
          image: hashicorp/http-echo:1.0.0
          args: ["-text=hello from v1","-listen=:8080"]
          ports: [{containerPort: 8080}]
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: web-v2, namespace: ch04-gw}
spec:
  replicas: 2
  selector: {matchLabels: {app: web, version: v2}}
  template:
    metadata: {labels: {app: web, version: v2}}
    spec:
      containers:
        - name: app
          image: hashicorp/http-echo:1.0.0
          args: ["-text=hello from v2","-listen=:8080"]
          ports: [{containerPort: 8080}]
---
apiVersion: v1
kind: Service
metadata: {name: web-v1, namespace: ch04-gw}
spec:
  selector: {app: web, version: v1}
  ports: [{port: 80, targetPort: 8080}]
---
apiVersion: v1
kind: Service
metadata: {name: web-v2, namespace: ch04-gw}
spec:
  selector: {app: web, version: v2}
  ports: [{port: 80, targetPort: 8080}]
```

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
metadata: {name: shared, namespace: ch04-gw}
spec:
  gatewayClassName: eg
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces: {from: All}   # 他 ns の Route も付けられるように
```

```bash
kubectl apply -f apps.yaml -f gateway.yaml
kubectl -n ch04-gw get gateway shared
```

### 3. HTTPRoute の **weight でカナリア**

```yaml
# httproute-canary.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: web, namespace: ch04-gw}
spec:
  parentRefs:
    - name: shared
  hostnames: ["app.local"]
  rules:
    - matches: [{path: {type: PathPrefix, value: /}}]
      backendRefs:
        - {name: web-v1, port: 80, weight: 80}
        - {name: web-v2, port: 80, weight: 20}
```

```bash
kubectl apply -f httproute-canary.yaml

# host の 80 → kind の control-plane → Envoy
for i in $(seq 1 50); do
  curl -s -H 'Host: app.local' http://localhost/
done | sort | uniq -c
# 期待: 約 40:10 で v1/v2
```

**weight を変えて再 apply** → 分配比率が即変わる:

```bash
kubectl -n ch04-gw patch httproute web --type=json -p='[
  {"op":"replace","path":"/spec/rules/0/backendRefs/0/weight","value":50},
  {"op":"replace","path":"/spec/rules/0/backendRefs/1/weight","value":50}
]'
for i in $(seq 1 50); do curl -s -H 'Host: app.local' http://localhost/; done | sort | uniq -c
```

### 4. **GRPCRoute** で gRPC を分配

```yaml
# grpc-app.yaml
apiVersion: apps/v1
kind: Deployment
metadata: {name: grpc-echo, namespace: ch04-gw}
spec:
  replicas: 1
  selector: {matchLabels: {app: grpc-echo}}
  template:
    metadata: {labels: {app: grpc-echo}}
    spec:
      containers:
        - name: server
          image: ghcr.io/projectcontour/yages:v0.1.0  # 軽量な gRPC echo
          ports: [{containerPort: 9000, name: grpc}]
---
apiVersion: v1
kind: Service
metadata: {name: grpc-echo, namespace: ch04-gw}
spec:
  selector: {app: grpc-echo}
  ports: [{port: 9000, targetPort: 9000, appProtocol: grpc}]
---
apiVersion: gateway.networking.k8s.io/v1
kind: GRPCRoute
metadata: {name: grpc, namespace: ch04-gw}
spec:
  parentRefs:
    - name: shared
  hostnames: ["grpc.local"]
  rules:
    - backendRefs:
        - {name: grpc-echo, port: 9000}
```

> Envoy Gateway は HTTP/2 を listener で自動扱い。GRPCRoute も `HTTPRoute` と同じ親 (Gateway) に付けられる。grpcurl を持っていれば `grpcurl -plaintext -authority grpc.local localhost:80 yages.Echo/Ping` で叩けます。

```bash
kubectl apply -f grpc-app.yaml
kubectl -n ch04-gw get grpcroute grpc
```

### 5. **ReferenceGrant** で cross-namespace backend

backend を **別 namespace** (`ch04-backend`) に置いて、HTTPRoute から参照:

```yaml
# backend-other-ns.yaml
apiVersion: apps/v1
kind: Deployment
metadata: {name: legacy, namespace: ch04-backend}
spec:
  replicas: 1
  selector: {matchLabels: {app: legacy}}
  template:
    metadata: {labels: {app: legacy}}
    spec:
      containers:
        - name: app
          image: hashicorp/http-echo:1.0.0
          args: ["-text=hello from legacy ns","-listen=:8080"]
          ports: [{containerPort: 8080}]
---
apiVersion: v1
kind: Service
metadata: {name: legacy, namespace: ch04-backend}
spec:
  selector: {app: legacy}
  ports: [{port: 80, targetPort: 8080}]
---
# 別 ns からの参照を許可 (被参照側に置くのがポイント)
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata: {name: allow-from-ch04-gw, namespace: ch04-backend}
spec:
  from:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      namespace: ch04-gw
  to:
    - group: ""
      kind: Service
```

HTTPRoute 側で `/legacy` を `ch04-backend/legacy` に飛ばす:

```yaml
# httproute-xref.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: web-xref, namespace: ch04-gw}
spec:
  parentRefs:
    - name: shared
  hostnames: ["app.local"]
  rules:
    - matches: [{path: {type: PathPrefix, value: /legacy}}]
      backendRefs:
        - name: legacy
          namespace: ch04-backend     # ← 別 ns 参照
          port: 80
```

```bash
kubectl apply -f backend-other-ns.yaml -f httproute-xref.yaml
curl -s -H 'Host: app.local' http://localhost/legacy
# → hello from legacy ns
```

**実験:** `ReferenceGrant` を消すと **HTTPRoute の status に `RefNotPermitted`** が出て届かなくなる:

```bash
kubectl -n ch04-backend delete referencegrant allow-from-ch04-gw
sleep 3
curl -i -s -H 'Host: app.local' http://localhost/legacy | head -1
# → 500 / 503 系
kubectl -n ch04-gw describe httproute web-xref | grep -A2 Conditions
```

復活させる:

```bash
kubectl apply -f backend-other-ns.yaml   # ReferenceGrant 含む
```

### 6. GAMMA の触り (概念だけ)

mesh 内 routing は、**同じ HTTPRoute** の `parentRefs` を **`kind: Service`** に切り替えるだけ:

```yaml
# 例: mesh 内で web Service のトラフィックを v1:v2=50:50 にする
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: web-mesh, namespace: ch04-gw}
spec:
  parentRefs:
    - group: ""
      kind: Service
      name: web                  # ← Gateway ではなく Service
  rules:
    - backendRefs:
        - {name: web-v1, port: 80, weight: 50}
        - {name: web-v2, port: 80, weight: 50}
```

Envoy Gateway 単体では mesh は提供されないので、ここでは **書ける** ことだけ確認 (apply はスキップで OK)。実体は Istio Ambient / Cilium Service Mesh が拾う領域です。

### 7. Ingress との対応 (おさらい)

| 機能 | Ingress | Gateway API |
|---|---|---|
| 入り口リソース | `Ingress` (1 個に全部) | `GatewayClass` + `Gateway` + `*Route` |
| カナリア | ベンダ独自 annotation | `backendRefs[].weight` 標準 |
| L4 / gRPC | 不可 / 限定的 | `TCPRoute` / `GRPCRoute` |
| cross-namespace backend | 不可 | `ReferenceGrant` で許可制 |
| ロール分離 | 不明確 | リソース粒度で明確 |
| Service Mesh 連携 | 別物 | GAMMA で統一 |

### 8. 後片付け

```bash
kubectl delete ns ch04-gw ch04-backend
helm -n envoy-gateway-system uninstall eg
kubectl delete ns envoy-gateway-system
# CRD は再利用するので残す。完全に消すなら:
# kubectl delete -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml
```

## やってみて気づくこと

- **weight を patch するだけ** で分配比率が即変わる気持ちよさ (Ingress + nginx annotation との対比)
- **GRPCRoute** が `HTTPRoute` と同じ Gateway にぶら下がる、用途別 Route の使い分けの自然さ
- **ReferenceGrant が "被参照側" に置く** という許可モデル。SOC / 監査の語彙に翻訳しやすい
- **GAMMA で mesh と統一** は、長期的に "Ingress / Service Mesh で別ツール" を吸収していく方向感

## 参考

- Gateway API: https://gateway-api.sigs.k8s.io/
- Envoy Gateway: https://gateway.envoyproxy.io/
- ReferenceGrant: https://gateway-api.sigs.k8s.io/api-types/referencegrant/
- GAMMA initiative: https://gateway-api.sigs.k8s.io/concepts/gamma/
- GRPCRoute: https://gateway-api.sigs.k8s.io/api-types/grpcroute/
- Gateway API GA blog: https://kubernetes.io/blog/2023/10/31/gateway-api-ga/
