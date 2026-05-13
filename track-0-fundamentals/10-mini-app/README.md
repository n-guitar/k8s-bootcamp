# 10 — Mini App: Web / AP / DB を組み合わせる (卒業課題)

## ゴール
これまでの 9 章で学んだオブジェクトを **組み合わせて**、3 層アプリを kind 上に公開する。
旧 bootcamp のゴール (chapter8) を v1.33 + Gateway API + PSA でリブートしたもの。

---

## 🤔 なぜ必要？ (ストーリー)

> あなたは部品 (Pod, Deployment, Service, ConfigMap, Secret, PVC, HTTPRoute, RBAC, PSA) を順番に学んだ。
> でも実際のアプリは **これらが噛み合って 1 つのサービス** になっている。
>
> ここでは、よくある 3 層 (Web / AP / DB) を組み立てて:
> - 部品同士がどう繋がるか **目で見る**
> - "**コードを書かずに**" 設定だけでデプロイ・更新・スケール・ロールバックが回ることを体感
> - PSA `baseline` で全 workload が動くことを確認 (本番想定の最低ライン)
>
> 「**ああ、これでようやく "Kubernetes 使ってる" って言える**」と感じる瞬間がゴール。

## ✨ 面白いポイント

- ここまで覚えた部品が、**そのまま同じ語彙のまま** 組み合わさる
- アプリの本体 (`app.py`) はたった 30 行、それを **YAML 6 個** がインフラ的に支える
- 一度組んだら、**DB の image を上げる / web の replicas を増やす / ConfigMap を書き換える** が **全部 1 行**

## 構成イメージ

```
                 ┌────────────────────────────────────────┐
                 │ HTTPRoute (host: app.local)            │
                 │   ↓ parentRef                          │
                 │ Gateway (shared, listener :80)         │
                 │   ↓ controllerName                     │
                 │ GatewayClass: eg (Envoy Gateway)       │
                 └────────────────────────────────────────┘
                                  ↓
   Service: web (ClusterIP)
   └─ Deployment: web (nginx, 2 replicas) ── reverse proxy → ap:8080
                                                     ↓
   Service: ap (ClusterIP)
   └─ Deployment: ap (FastAPI, 2 replicas)
        - ConfigMap: ap-config   (LOG_LEVEL, MESSAGE)
        - Secret:    db-cred     (DB_PASSWORD)
        └ Service: db (ClusterIP, headless)
          └ StatefulSet: db (postgres, replicas: 1)
              └ PVC: pgdata (1Gi, local-path)
```

## 前提

- 08 章までを通して進めていること (Envoy Gateway がクラスタに入っている)
- kind の extraPortMappings で host の 80 が抜けていること
- `/etc/hosts` に `127.0.0.1 app.local` (Mac/Linux) もしくは `localhost` で Host ヘッダを付けて curl

## やること

### 0. namespace 準備 (PSA baseline)

```bash
kubectl create ns mini-app
kubectl label ns mini-app pod-security.kubernetes.io/enforce=baseline --overwrite
```

### 1. DB 層 (StatefulSet + headless Service + PVC)

```yaml
# 1-db.yaml
apiVersion: v1
kind: Service
metadata: {name: db, namespace: mini-app}
spec:
  clusterIP: None
  selector: {app: db}
  ports: [{port: 5432, targetPort: 5432}]
---
apiVersion: apps/v1
kind: StatefulSet
metadata: {name: db, namespace: mini-app}
spec:
  serviceName: db
  replicas: 1
  selector: {matchLabels: {app: db}}
  template:
    metadata: {labels: {app: db}}
    spec:
      containers:
        - name: postgres
          image: postgres:16-alpine
          ports: [{containerPort: 5432}]
          env:
            - name: POSTGRES_DB
              value: app
            - name: POSTGRES_USER
              value: app
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef: {name: db-cred, key: DB_PASSWORD}
            - name: PGDATA
              value: /var/lib/postgresql/data/pgdata
          volumeMounts:
            - {name: data, mountPath: /var/lib/postgresql/data}
  volumeClaimTemplates:
    - metadata: {name: data}
      spec:
        accessModes: ["ReadWriteOnce"]
        resources: {requests: {storage: 1Gi}}
---
apiVersion: v1
kind: Secret
metadata: {name: db-cred, namespace: mini-app}
type: Opaque
stringData:
  DB_PASSWORD: "s3cret-please-change"
```

### 2. AP 層 (Deployment + ConfigMap + Service)

サンプル AP として小さな Python アプリを使う想定。ここでは **既存の OSS イメージ** で代用します:

```yaml
# 2-ap.yaml
apiVersion: v1
kind: ConfigMap
metadata: {name: ap-config, namespace: mini-app}
data:
  MESSAGE: "hello from ap, talking to postgres"
  LOG_LEVEL: "info"
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: ap, namespace: mini-app}
spec:
  replicas: 2
  selector: {matchLabels: {app: ap}}
  strategy:
    type: RollingUpdate
    rollingUpdate: {maxUnavailable: 0, maxSurge: 1}
  template:
    metadata: {labels: {app: ap}}
    spec:
      containers:
        - name: ap
          # 実プロジェクトではあなたのアプリを差し替え。ここではエコーサーバで代用
          image: hashicorp/http-echo:1.0.0
          args: ["-text=$(MESSAGE) [pw len=$(DBPW_LEN)]", "-listen=:8080"]
          env:
            - name: MESSAGE
              valueFrom: {configMapKeyRef: {name: ap-config, key: MESSAGE}}
            - name: DBPW_LEN          # Secret から長さを抜き出すデモ的注入
              value: "18"
          ports: [{containerPort: 8080}]
          readinessProbe: {httpGet: {path: /, port: 8080}, periodSeconds: 2}
---
apiVersion: v1
kind: Service
metadata: {name: ap, namespace: mini-app}
spec:
  selector: {app: ap}
  ports: [{port: 8080, targetPort: 8080}]
```

> 本格的な AP に置き換えるには、ConfigMap / Secret 注入を **環境変数 + volume** にし、`psycopg2` 等で `db.mini-app.svc.cluster.local:5432` に接続する実装にします。

### 3. Web 層 (nginx reverse proxy)

```yaml
# 3-web.yaml
apiVersion: v1
kind: ConfigMap
metadata: {name: web-config, namespace: mini-app}
data:
  default.conf: |
    server {
      listen 80;
      location / {
        proxy_pass http://ap.mini-app.svc.cluster.local:8080;
      }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: web, namespace: mini-app}
spec:
  replicas: 2
  selector: {matchLabels: {app: web}}
  template:
    metadata: {labels: {app: web}}
    spec:
      containers:
        - name: nginx
          image: nginx:1.27-alpine
          ports: [{containerPort: 80}]
          volumeMounts:
            - {name: cfg, mountPath: /etc/nginx/conf.d/}
      volumes:
        - name: cfg
          configMap: {name: web-config}
---
apiVersion: v1
kind: Service
metadata: {name: web, namespace: mini-app}
spec:
  selector: {app: web}
  ports: [{port: 80, targetPort: 80}]
```

### 4. 公開 (Gateway API)

```yaml
# 4-route.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: shared, namespace: mini-app}
spec:
  gatewayClassName: eg
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes: {namespaces: {from: Same}}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: web, namespace: mini-app}
spec:
  parentRefs: [{name: shared}]
  hostnames: ["app.local"]
  rules:
    - matches: [{path: {type: PathPrefix, value: /}}]
      backendRefs: [{name: web, port: 80}]
```

### 5. 一気に apply

```bash
kubectl apply -f 1-db.yaml
kubectl apply -f 2-ap.yaml
kubectl apply -f 3-web.yaml
kubectl apply -f 4-route.yaml
kubectl -n mini-app get pods -o wide
kubectl -n mini-app wait --for=condition=Ready pods --all --timeout=120s
```

### 6. 動作確認

```bash
curl -s -H 'Host: app.local' http://localhost/
# → "hello from ap, talking to postgres [pw len=18]"
```

### 7. 楽しい実験

| 実験 | コマンド | 観察 |
|---|---|---|
| Web スケール | `kubectl -n mini-app scale deploy/web --replicas=5` | EndpointSlice が即更新 |
| AP の MESSAGE 変更 | `kubectl -n mini-app edit cm ap-config` | env 注入なので **Pod を再起動するまで反映されない** |
| AP rolling restart | `kubectl -n mini-app rollout restart deploy/ap` | ダウンタイム 0 で更新 |
| ロールバック | `kubectl -n mini-app rollout undo deploy/ap` | 前世代に即戻る |
| DB Pod 削除 | `kubectl -n mini-app delete pod db-0` | StatefulSet が同じ名前で復元、PVC のデータは残る |

### 8. ゴールチェック (= 卒業条件)

- [ ] 全 Pod が `Running`
- [ ] `curl` でブラウザ相当の応答が返る
- [ ] PSA `baseline` でも全 workload が拒否されずに動く
- [ ] `kubectl rollout restart deploy/ap` でダウンタイム最小で更新できた
- [ ] `kubectl delete pod db-0` してもデータが残ることを確認 (PVC のおかげ)

### 9. 後片付け

```bash
kubectl delete ns mini-app
```

## やってみて気づくこと

- **YAML 4 ファイル = 1 つの本格的なアプリ**。これがインフラがコードに溶け込んだ世界
- 各層 (Web / AP / DB) は **Service 名** だけで疎結合 (IP も Pod 名も知らない)
- ConfigMap / Secret の注入方法 (env vs volume) の **再起動有無** の違いを実体験
- StatefulSet は Pod 名が固定 (`db-0`) で、消しても PVC とともに復元する

> **おめでとう! Track 0 卒業です。** ここから先は [Track A](../../track-a-local-kind/) で v1.22 → v1.33 の新機能群へ。

## 参考

- StatefulSet: https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/
- Pod Security Standards: https://kubernetes.io/docs/concepts/security/pod-security-standards/
- Gateway API: https://gateway-api.sigs.k8s.io/
