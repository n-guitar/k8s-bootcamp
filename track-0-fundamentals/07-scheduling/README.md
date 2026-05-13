# 07 — Scheduling

## ゴール
- scheduler が何を見て Pod を Node に配置するか
- `nodeSelector` / `Taint`+`Toleration` / `Affinity` / `topologySpreadConstraints` の使い分け
- `resources.requests / limits` がスケジューリングと QoS にどう効くか

---

## 🤔 なぜ必要？ (ストーリー)

> あなたのクラスタには 5 つの Node がある。
> - 2 つは普通のサーバ
> - 2 つは GPU 付き (ML 用)
> - 1 つはステージング用に隔離したい
>
> ある日、Pod が 100 個立った。scheduler は **何も指示しないと均等に撒く**。
> → GPU Node に nginx が乗り、ML 用 Pod が普通 Node にスケジュールされて GPU が使えない大事故。
>
> あるいは:
> - 「同じアプリの 3 つの Pod を **別々の Zone** に置きたい」(障害分散)
> - 「Web Pod と Cache Pod は **同じ Node** に置きたい」(レイテンシ短縮)
> - 「Pod の CPU 使用が暴走したら Node ごと巻き込まれるのを防ぎたい」
>
> これらの "配置のヒント" を YAML で書くのが、本章のテーマです。

## ✨ 面白いポイント (設計)

### 1. **scheduler = "**ふるい落とし + スコアリング**"**

```
1. Filter (predicate): 「載せられる」Node だけ残す
   - resources.requests に足りる Node か
   - taint と一致する toleration を持つか
   - nodeSelector / affinity に合うか
2. Score (priority):   残った Node を 0〜100 でスコアリング
   - すでに同じ Pod がいない Node を高く (分散)
   - リソース余裕のある Node を高く
   - affinity / anti-affinity / topology
3. Bind:               一番スコアが高い Node に Pod.spec.nodeName を書く
```

> **痺れ所:** scheduler は **API server 経由で `Pod.spec.nodeName` を書くだけ**。
> 実際の起動はその Node の kubelet が watch して引き取る。**疎結合**。

### 2. **Taint と Toleration の "**逆向き**" 思想**

普通の "selector" は **Pod が "ここ来たい"** と言う:
```yaml
nodeSelector: { gpu: "true" }
```

Taint は逆で **Node が "余計な Pod 来るな"** と言う:
```bash
kubectl taint nodes gpu-node gpu=true:NoSchedule
```

→ "**gpu=true の Toleration を持つ Pod だけ受け入れる**"。
ML 用 Pod だけが GPU Node に乗る。一般 Pod は弾かれる。

> **痺れ所:** 拒否権を **Node 側** に持たせた。「指定された者以外は来るな」を一行で書ける。

### 3. **Pod Affinity / Anti-Affinity の "**ラベルベース**"**

「Cache と一緒に置きたい」「同じ Web を別 Node に分けたい」を **ラベルセレクタ** で書く:

```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector: { matchLabels: { app: web } }
          topologyKey: kubernetes.io/hostname
```

→ 「`app=web` の Pod が **既にいる Node** は避ける」。
ハードに強制したいなら `requiredDuringSchedulingIgnoredDuringExecution`。

### 4. **`topologySpreadConstraints` = "**綺麗に分散**" の宣言**

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: ScheduleAnyway
    labelSelector: { matchLabels: { app: web } }
```

→ 「`app=web` の Pod を **zone ごとの個数差 ≤ 1** で配置」。
Pod Anti-Affinity の "なるべく分散" を、より宣言的に書ける。

### 5. **`resources.requests` と QoS Class**

| requests / limits | QoS Class | 動き |
|---|---|---|
| 両方指定 (同値) | **Guaranteed** | 最後に kill される |
| 両方指定 (異なる) または requests のみ | **Burstable** | 中間 |
| 何も指定なし | **BestEffort** | 真っ先に kill される |

> **痺れ所:** requests は **スケジューリング判断** に、limits は **cgroup 強制** に使う。 役割が違うことに気付くと、resource 設計の見方が変わる。

## 😱 あるある罠

- **requests を書かない**: Node のリソースが見かけ上余って見え、すぐ OOM
- **limits=requests を信仰**: CPU で limits を厳しく付けると **CPU throttling** で性能ガタ落ち。CPU は requests のみ、memory は limits も付ける、が現代的
- **`nodeSelector` だけで GPU 隔離**: 他の Pod がスケジュールされて GPU 占有不能 → **必ず Taint と併用**
- **Anti-Affinity の `required`**: 厳格すぎてスケールアウトできない。**preferred** で書く方が現実的
- **`topology.kubernetes.io/zone` ラベルが Node に無い**: spread が効かない。kind なら自分で `kubectl label` する

## やること

### 0. 準備

```bash
kubectl create ns ch07 --dry-run=client -o yaml | kubectl apply -f -
kubectl label ns ch07 pod-security.kubernetes.io/enforce=baseline --overwrite
# ↑ baseline ラベルは「Pod の特権昇格を防ぐ標準のガード」。09 章で詳説。今は "本番想定の最低ライン" と覚えて進めて OK。
kubectl get nodes --show-labels
```

### 1. Node ラベルを確認 (kind-config で既に貼ってある)

`track-0-fundamentals/kind-config.yaml` を使ってクラスタを立てた人は、worker に `tier=app` と **標準ラベル** `topology.kubernetes.io/zone=za / zb` が既に貼られています:

```bash
kubectl get nodes -L tier,topology.kubernetes.io/zone
# bootcamp-worker   Ready  <none>  ...  app  za
# bootcamp-worker2  Ready  <none>  ...  app  zb
```

> 標準ラベル `topology.kubernetes.io/zone` を使うのは、後述の `topologySpreadConstraints` が **クラウドでも同じキー** で動くため。自分用に独自キーを使うなら `zone` でも問題ありませんが、現場の慣例に合わせます。

(ラベルが付いていなければ手動で:)
```bash
kubectl label node bootcamp-worker  tier=app topology.kubernetes.io/zone=za --overwrite
kubectl label node bootcamp-worker2 tier=app topology.kubernetes.io/zone=zb --overwrite
```

### 2. `nodeSelector` で配置を固定

```yaml
# selector.yaml
apiVersion: v1
kind: Pod
metadata: {name: pinned, namespace: ch07}
spec:
  nodeSelector:
    topology.kubernetes.io/zone: za
  containers: [{name: c, image: nginx:1.27}]
```

```bash
kubectl apply -f selector.yaml
kubectl -n ch07 get pod pinned -o wide   # NODE が bootcamp-worker
```

### 3. Taint で隔離を表現

```bash
kubectl taint nodes bootcamp-worker2 dedicated=ml:NoSchedule
```

```yaml
# normal.yaml — toleration なし
apiVersion: v1
kind: Pod
metadata: {name: ordinary, namespace: ch07}
spec:
  containers: [{name: c, image: nginx:1.27}]
```

```yaml
# ml.yaml — toleration あり
apiVersion: v1
kind: Pod
metadata: {name: ml-job, namespace: ch07}
spec:
  tolerations:
    - key: dedicated
      operator: Equal
      value: ml
      effect: NoSchedule
  containers: [{name: c, image: nginx:1.27}]
```

```bash
kubectl apply -f normal.yaml -f ml.yaml
kubectl -n ch07 get pod -o wide
# ordinary は bootcamp-worker のみ、ml-job は worker2 にも乗れる
```

後片付け:
```bash
kubectl taint nodes bootcamp-worker2 dedicated=ml:NoSchedule-
```

### 4. Pod Anti-Affinity でスケールを分散

```yaml
# antiaff.yaml
apiVersion: apps/v1
kind: Deployment
metadata: {name: web, namespace: ch07}
spec:
  replicas: 4
  selector: {matchLabels: {app: web}}
  template:
    metadata: {labels: {app: web}}
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector: {matchLabels: {app: web}}
                topologyKey: kubernetes.io/hostname
      containers:
        - name: nginx
          image: nginx:1.27
          resources:
            requests: {cpu: 50m, memory: 32Mi}
```

```bash
kubectl apply -f antiaff.yaml
kubectl -n ch07 get pod -o wide
# → なるべく Node が分散する
```

### 5. topologySpreadConstraints (zone ラベルを使う)

```yaml
# spread.yaml (Deployment の spec.template.spec に下記を追加)
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: ScheduleAnyway
    labelSelector: {matchLabels: {app: web}}
```

apply 後 `-o wide` で zone 列を見ると、za / zb の差が ≤ 1 に収まることを観察。

### 6. resources & QoS Class

```yaml
# qos.yaml
apiVersion: v1
kind: Pod
metadata: {name: gtd, namespace: ch07}
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: ["sleep", "3600"]
      resources:
        requests: {cpu: 100m, memory: 64Mi}
        limits:   {cpu: 100m, memory: 64Mi}   # 両方同値 → Guaranteed
```

```bash
kubectl apply -f qos.yaml
kubectl -n ch07 get pod gtd -o jsonpath='{.status.qosClass}'    # → Guaranteed
```

### 7. 後片付け

```bash
kubectl delete ns ch07
# tier ラベルは Track 0 全体で使わないのでクリーンアップしてよい (zone は kind-config 側で再生成)
kubectl label node bootcamp-worker  tier-
kubectl label node bootcamp-worker2 tier-
```

## やってみて気づくこと

- scheduler は "**選ぶ**" だけ。実行は kubelet。疎結合の徹底
- **Taint と Toleration はペア** で初めて意味を持つ
- `preferred*` は **柔らかい希望**、`required*` は **厳格な強制**。本番は preferred が無難
- requests を書く / 書かないだけで **QoS Class が決まる** 事実は知っておくと OOM 解析の役に立つ

> **冒頭のストーリーへの答え合わせ:**
> - 「GPU Node に nginx が乗る大事故」 → Taint `dedicated=ml:NoSchedule` で **拒否権を Node に持たせて** 解決
> - 「同じアプリ 3 つを別 Zone に」 → `topologySpreadConstraints` で **maxSkew: 1** を宣言
> - 「Web と Cache を同 Node に置きたい」 → `podAffinity` で同居を表現
> - 「Pod が暴走しても Node を巻き込まれたくない」 → `resources.limits` で cgroup 強制
>
> 全部 **scheduler に対する "**配置のヒント**" を YAML で書くだけ**。手で割り振らない。

## 参考

- Scheduling: https://kubernetes.io/docs/concepts/scheduling-eviction/
- Affinity: https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/
- Taint and Toleration: https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/
- Topology Spread: https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/
- QoS Class: https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/
