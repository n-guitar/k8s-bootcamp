# 04 — Service と DNS

## ゴール
- なぜ **Pod IP を直接使わないか** を理解
- **Service** 4 タイプ (ClusterIP / NodePort / LoadBalancer / ExternalName) の用途分け
- クラスタ内 **DNS** (`<svc>.<ns>.svc.cluster.local`)
- **EndpointSlice** という裏側

---

## 🤔 なぜ必要？ (ストーリー)

> あなたは Deployment で 3 つの Pod を立てた。それぞれ IP が振られている。
> アプリ B から呼びたい時、3 つの IP のどれを叩けばいい?
> しかも Pod は **死ぬたびに IP が変わる**。
>
> 「**じゃあロードバランサを立てれば**」と思った直後:
> - ロードバランサのバックエンドプール、誰が更新するの?
> - Pod が死んで IP が変わったら、誰が LB から外すの?
> - Pod が増えたら、誰が LB に足すの?
>
> → 「Pod の集合に **安定した名前と IP** を与え、自動で endpoint を追従する」仕組みが要る。
> それが **Service** です。

## ✨ 面白いポイント (設計)

### 1. **Service = "**動的に変わる Pod 集合**" への "**安定した宛先**"**

- ClusterIP は **死なない仮想 IP** (実体は kube-proxy / Cilium が iptables/eBPF で配る)
- バックエンドのリストは **EndpointSlice** が自動で更新
- Pod のラベル (`app=web`) が一致するだけで自動 join → **疎結合**

> **痺れ所:** Service と Pod は **ラベル** だけで繋がる。Service は「`app=web` を見て、生きてるやつに振り分け」と書くだけ。
> 後から Pod を増減しても、Service の YAML を書き換える必要は **ゼロ**。

### 2. **DNS が "**一級市民**"**

CoreDNS が `kube-system` に常駐し、`<svc>.<ns>.svc.cluster.local` を解決する。
Pod の `/etc/resolv.conf` は **自動で** クラスタ DNS を向く。

```
api.payment.svc.cluster.local
^   ^       ^
|   |       └─ サフィックス (固定)
|   └────── namespace
└────────── service 名
```

短縮形:
- 同 namespace 内なら `api` だけで届く (`search` リストのおかげ)
- 別 namespace なら `api.payment` まで書けば届く

> **痺れ所:** 名前で疎結合になるので、Pod IP を **アプリが直接知る必要は永遠に無い**。これが「**移植可能なアプリ**」の鍵。

### 3. **EndpointSlice (旧 Endpoints からの進化)**

昔は `Endpoints` という 1 個の巨大オブジェクトに全エンドポイントが詰め込まれていた。
1 Pod 変わるたびに全 Endpoints を書き換え → API server に負荷集中。

v1.21 以降は **EndpointSlice** に分割: 100 endpoint ごとに 1 slice。
**変更の波及範囲を小さくした** のが偉い。

### 4. **kube-proxy → Cilium への流れ**

Service IP を実際にルーティングしているのは kube-proxy (iptables/IPVS)。
ただし大規模だと iptables が遅い → Track A 06 で **Cilium が eBPF で置き換える** 話に繋がる。

## 😱 あるある罠

- **selector のラベル不一致**: Service の selector が Pod のラベルと 1 文字でも違うと、Endpoints が空。`kubectl get endpointslice -l kubernetes.io/service-name=<svc>` で 0 件なら疑う
- **`type: LoadBalancer` を本番で素朴に使う**: 各 Service ごとに ALB/NLB が出来る → コストが膨れる。**Gateway API / Ingress に集約** が正解 (08 章)
- **Headless Service (`clusterIP: None`) を知らない**: StatefulSet で各 Pod に DNS を生やす時に必須
- **`session affinity` の罠**: 「同じ IP の人を同じ Pod に」を期待しても、デフォルトは無効。`sessionAffinity: ClientIP` が必要

## やること

### 0. 準備

```bash
kubectl create ns ch04 --dry-run=client -o yaml | kubectl apply -f -
kubectl label ns ch04 pod-security.kubernetes.io/enforce=baseline --overwrite
# ↑ baseline ラベルは「Pod の特権昇格を防ぐ標準のガード」。09 章で詳説。今は "本番想定の最低ライン" と覚えて進めて OK。
```

### 1. Deployment + ClusterIP Service

```yaml
# web.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: ch04
spec:
  replicas: 3
  selector: {matchLabels: {app: web}}
  template:
    metadata: {labels: {app: web}}
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          ports: [{containerPort: 80}]
---
apiVersion: v1
kind: Service
metadata:
  name: web
  namespace: ch04
spec:
  type: ClusterIP
  selector: {app: web}   # ← これが疎結合の核
  ports:
    - port: 80
      targetPort: 80
```

```bash
kubectl apply -f web.yaml
kubectl -n ch04 get svc web
kubectl -n ch04 get endpointslice -l kubernetes.io/service-name=web
# → 3 つの Pod IP が並んでいるはず
```

### 2. クライアント Pod から DNS で叩く

`curlimages/curl` には `sh` が無いので、busybox で 1 ショット実行します。

```bash
# DNS 解決の確認
kubectl -n ch04 run dns-test --rm -i --restart=Never \
  --image=busybox:1.36 -- nslookup web
# → Address: <ClusterIP>  / Name: web.ch04.svc.cluster.local

# HTTP で 5 回叩く (ロードバランスの体感)
kubectl -n ch04 run curl-test --rm -i --restart=Never \
  --image=busybox:1.36 --command -- sh -c \
  'for i in 1 2 3 4 5; do wget -qS -O /dev/null http://web 2>&1 | grep HTTP/; done'
# → "HTTP/1.1 200 OK" が 5 行
```

### 3. 「Pod を 1 個消す」と "**勝手に振り分け先が更新される**"

別ターミナルで:
```bash
kubectl -n ch04 get endpointslice -l kubernetes.io/service-name=web -w
```

```bash
kubectl -n ch04 delete pod -l app=web --field-selector status.phase=Running | head -1
```

→ EndpointSlice から該当 IP が消え、新 Pod の IP に置き換わるのを観察。

### 4. NodePort で host から到達

```yaml
# web-nodeport.yaml (patch)
apiVersion: v1
kind: Service
metadata:
  name: web-np
  namespace: ch04
spec:
  type: NodePort
  selector: {app: web}
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30080
```

```bash
kubectl apply -f web-nodeport.yaml
# kind の場合は extraPortMappings に 30080 が無いと届かないので、curl は kind node 内から
docker exec bootcamp-control-plane curl -s http://localhost:30080 | head
```

> 本番で `NodePort` を直接公開するのは **非推奨**。学習目的のみ。

### 5. Headless Service の感触 (StatefulSet の予習)

```yaml
# headless.yaml
apiVersion: v1
kind: Service
metadata:
  name: web-headless
  namespace: ch04
spec:
  clusterIP: None
  selector: {app: web}
  ports: [{port: 80, targetPort: 80}]
```

```bash
kubectl apply -f headless.yaml
kubectl -n ch04 run debug --image=busybox:1.36 --restart=Never -it --rm -- nslookup web-headless
# → 個々の Pod IP が A レコードで返る (= LB しない)
```

### 6. 後片付け

```bash
kubectl delete ns ch04
```

## やってみて気づくこと

- Service は **IP を持たない動的なバックエンドの集合に "**名前**" を与える** だけのもの
- ラベルセレクタの威力 (Pod を増減しても Service は無変更)
- DNS が前提なので、アプリは **IP を知らなくていい**
- Headless Service は LB しない代わりに **個別 Pod を直接指せる** (= StatefulSet で使う)

## 参考

- Service: https://kubernetes.io/docs/concepts/services-networking/service/
- DNS for Services: https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/
- EndpointSlice: https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/
