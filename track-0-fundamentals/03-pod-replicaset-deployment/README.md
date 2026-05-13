# 03 — Pod / ReplicaSet / Deployment

## ゴール
- **Pod** = k8s で動かす最小単位 (= 1 つ以上のコンテナ + 共有 net/IPC)
- **ReplicaSet** = 「N 個動いてて欲しい」を維持する人
- **Deployment** = ReplicaSet を「ローリングで入れ替え」できるようにした人

---

## 🤔 なぜ必要？ (ストーリー)

> あなたは前章で nginx の Pod を 1 つ立てた。
> ふと `kubectl delete pod my-nginx` を試したら、当然消えた。**何も復活しない。**
> 「常に 1 個動いていてほしい」のに、人間が見張ってないと消えたまま。
>
> 翌日、上司:「アクセス増えたから 3 台にして」
> あなた:「Pod 3 つ作ります」
> → でも 1 つ落ちたら 2 つに減ったまま。**自動で 3 つを保つ仕組みが欲しい。**
>
> その夜、また上司:「アプリのバージョン上げて」
> → 3 つ消して新しいの 3 つ作る? その間 502? **ローリング更新が欲しい。**

この 3 段の痛みに、それぞれ Pod / ReplicaSet / Deployment が答えます。

```
Pod         : 動かす最小単位。落ちても誰も拾わない
  ↓
ReplicaSet  : "N 個保つ" を約束する。落ちたら自動で作り直す
  ↓
Deployment  : 新 ReplicaSet と旧 ReplicaSet を **同時に持ち**、徐々に切替
```

## ✨ 面白いポイント (設計)

### 1. **Pod = "**コンテナの単位ではなく**" "スケジューリングの単位"**

Pod の中には複数コンテナを入れられる。同じ Pod のコンテナは:
- **同じ Node** に必ず一緒に置かれる
- **同じネットワーク名前空間** (= `localhost` で会話)
- **同じ Volume** を共有できる

> **痺れ所:** 「1 コンテナ = 1 アプリ」というシンプルさを守りつつ、
> 「ログ収集 sidecar」「proxy sidecar」など **協調するプロセス群を 1 単位で扱う** ためにレイヤをもう 1 つ作った。これは Track A 03 でさらに進化する (KEP-753)。

### 2. **ReplicaSet = "**Reconcile Loop の見本市**"**

ReplicaSet controller のロジックは、教科書的にはこれだけ:

```
loop forever:
    desired  = spec.replicas
    current  = count(matching Pods)
    if current < desired:
        create (desired - current) Pods
    elif current > desired:
        delete (current - desired) Pods
```

それだけ。なのに、これがあるおかげで:
- Node が落ちて Pod が消える → 自動で他 Node に作り直す
- 誤って `kubectl delete pod` → 自動で復活
- 手動で `kubectl scale` → desired を変えると即座に追従

**「シンプルなループの繰り返しが、複雑な運用を消す」**。これが k8s の中核思想。

### 3. **Deployment の "**新旧 ReplicaSet 並行**" トリック**

Deployment は ReplicaSet を **直接書き換えない**。
代わりに、新しい ReplicaSet を `replicas: 0` で作り、徐々に増やしながら旧 ReplicaSet を減らす。

```
旧 RS (replicas: 3) ─┐    ─→ 旧 RS (2)    ─→ 旧 RS (1)    ─→ 旧 RS (0)
                     │
新 RS (replicas: 0) ─┘    ─→ 新 RS (1)    ─→ 新 RS (2)    ─→ 新 RS (3)
```

途中で問題があれば `kubectl rollout undo` → 旧 RS を再度増やすだけ。
**ロールバックが "新 ReplicaSet を捨てる" だけ** で済む。

## 😱 あるある罠

- **Pod を直接 `kubectl run` で運用**: 再起動されない。常に Deployment 経由で
- **`replicas` を YAML に書いたまま HPA 併用**: GitOps で reconcile される度に HPA の値が打ち消される → Deployment では HPA 利用時 `replicas` を **書かない** (またはサーバサイド apply のフィールドオーナーシップを理解)
- **`image: nginx:latest`**: 同じマニフェストを apply しても何も変わらず、Pod が更新されない → 必ずバージョン明示
- **`imagePullPolicy: Always` を本番で多用**: rolling 中に registry が落ちると全 Pod が起動できない事故。タグが固定なら `IfNotPresent`

## やること

### 0. 準備

```bash
kubectl create ns ch03
kubectl label ns ch03 pod-security.kubernetes.io/enforce=baseline --overwrite
```

### 1. Pod 単体 — "消えたら戻ってこない" を体感

```yaml
# pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: solo
  namespace: ch03
spec:
  containers:
    - name: web
      image: nginx:1.27
      ports: [{containerPort: 80}]
```

```bash
kubectl apply -f pod.yaml
kubectl -n ch03 get pod -w  # 別ターミナルで眺める
kubectl -n ch03 delete pod solo
# → solo は消えたまま。誰も拾わない。
```

### 2. ReplicaSet — "落としても勝手に戻る" を体感

```yaml
# rs.yaml
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: web-rs
  namespace: ch03
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          ports: [{containerPort: 80}]
```

```bash
kubectl apply -f rs.yaml
kubectl -n ch03 get pods -l app=web
# 1 個わざと殺す
kubectl -n ch03 delete pod -l app=web --field-selector status.phase=Running | head -1
# → 即座に新しい Pod が作られる
kubectl -n ch03 get rs web-rs
```

**実験:** `replicas: 5` に書き換えて再 apply → 2 個 increase。**スケールはこれだけ**。

### 3. Deployment — ローリング更新を体感

```yaml
# deploy.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: ch03
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0   # ダウンタイム 0 を狙う
      maxSurge: 1
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          ports: [{containerPort: 80}]
          readinessProbe:
            httpGet: {path: /, port: 80}
            periodSeconds: 2
```

```bash
kubectl delete rs web-rs -n ch03    # 前章のを消す
kubectl apply -f deploy.yaml
kubectl -n ch03 rollout status deploy/web
```

**バージョンを上げる:**

```bash
kubectl -n ch03 set image deploy/web nginx=nginx:1.28
kubectl -n ch03 rollout status deploy/web
kubectl -n ch03 get rs    # ← 新旧 ReplicaSet が並んでいる時間が一瞬ある
```

**ロールバック:**

```bash
kubectl -n ch03 rollout undo deploy/web
kubectl -n ch03 rollout history deploy/web
```

### 4. 後片付け

```bash
kubectl delete ns ch03
```

## やってみて気づくこと

- **Pod を消しても誰も拾わないこと** が、逆に "ReplicaSet がやってくれてる事の重さ" を実感させる
- ReplicaSet の正体は **数を保つループ**、それだけ
- Deployment の `kubectl get rs` で新旧 2 つの ReplicaSet が一瞬並ぶ事実を一度見ると、**ローリング更新の仕組みが視覚化される**
- `kubectl rollout undo` が一瞬で効くのは、旧 ReplicaSet が **削除されずに残っている** から (デフォルト 10 世代)

## 参考

- Pod: https://kubernetes.io/docs/concepts/workloads/pods/
- ReplicaSet: https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/
- Deployment: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/
- readiness/liveness: https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/
