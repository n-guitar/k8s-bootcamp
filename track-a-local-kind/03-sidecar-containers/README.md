# 03 — Sidecar Containers (KEP-753)

## ゴール
- v1.29 で beta, **v1.33 で GA** となった **ネイティブ Sidecar Containers** を理解
- 旧来の "`spec.containers` に sidecar を並べる" 流派の **痛み** を体感
- `initContainers[].restartPolicy: Always` で **起動順序 / 終了順序 / Job 完走** がどう変わるかを観察
- logging / service-mesh proxy injection が、なぜこの仕様を渇望していたかを腹落ち

---

## 🤔 なぜ必要？ (ストーリー)

> ある日、データパイプラインの夜間 Job が「**完了しない**」と Slack に上がってきた。
> ```
> Job: backup-export
> Pods: 0 Succeeded / 0 Failed / 1 Running  (8時間)
> ```
> ログを見ると本体 (`mysqldump`) は **20 分で正常終了** している。
> なのに Pod は Running。
>
> Pod を覗くと、**sidecar の `fluentd` がずっと走っていた**。
> Job の本体は終わっているのに、ログ送信 sidecar が永久ループ → Pod が Terminated にならない → Job が Succeeded に遷移しない。
>
> 「**じゃあ sidecar に終了シグナル送るやつを Bash で書きました**」
> → 翌週、別チーム:「Istio の envoy proxy が起動する前に init コンテナが外部 API を叩いて失敗します」
> → 「**起動順序を保証する shell script ラッパー**」を書く羽目に。
>
> "**メインの起動前に sidecar を上げ、メインが終わったら sidecar も下げる**"
> ——これだけの願いがなぜ 7 年も叶わなかったか。**KEP-753** がやっと終止符を打ったのが v1.33 (GA)。

## ✨ 面白いポイント (設計)

### 1. **新しいフィールドを増やさず、既存フィールドの "意味" を拡張した**

```yaml
spec:
  initContainers:
    - name: logger
      image: fluent/fluent-bit:3.0
      restartPolicy: Always   # ← これだけ
  containers:
    - name: main
      image: busybox:1.36
```

`initContainers` は元々 "main の前に走る、終わったら捨てる" コンテナだった。
そこに **`restartPolicy: Always` を書いただけで sidecar 扱いに格上げ**。

> **痺れ所:** **API を増やすのではなく、既存の意味を拡張する** という API design の手本。`SidecarContainer` という新 kind / 新フィールドを作ったら、controller も RBAC も全部触る羽目になる。

### 2. **保証されるライフサイクル**

- **起動**: sidecar (`initContainers[].restartPolicy: Always`) → main の順
- **終了**: main → sidecar の順
- **Job 完走**: **main が exit したら sidecar も SIGTERM** → Pod は Terminated → Job が Succeeded

```
       start ─→  sidecar A
                  │
                  ├─→  sidecar B
                  │
                  ├─→  main   ─→ exit
                  │              │
                  ├← SIGTERM ←──┘
                  ↓
                terminated
```

### 3. **既存パターンが要らなくなる**

| 旧パターン | やってた工夫 | KEP-753 で要らなくなる |
|---|---|---|
| logging sidecar (fluent-bit) + Job | preStop hook で fluent-bit を kill する script | 自動 |
| Istio sidecar injection | `holdApplicationUntilProxyStarts` などの設定 | restartPolicy: Always で順序保証 |
| DB proxy (cloudsql-proxy) | health probe で proxy が立つまで main を待つ | 同上 |

> **痺れ所:** "**過去 7 年間に書かれた何千行の shell script**" が、API の 1 フィールドで消える瞬間。

## 😱 あるある罠

- **`restartPolicy: Always` を Pod 直下に書く**: Pod 本体の `restartPolicy` (`Always`/`OnFailure`/`Never`) と **別物**。**コンテナ内の** フィールドである点に注意
- **古いクラスタ (< v1.28) で書く**: フィールドが無視され "init として 1 回走って終わる" 旧来挙動になる。**v1.29+ で feature gate, v1.33 で GA**
- **sidecar が長時間 startup probe で待つ**: 順序保証は startup probe (もしくは無ければ起動完了) 待ち。`startupProbe` を sidecar に書かないと、起動完了の判定が早すぎることが
- **sidecar 内の SIGTERM 取りこぼし**: アプリ側が SIGTERM を握っていないと、main 終了後に sidecar が gracefully 落ちず `terminationGracePeriodSeconds` を使い切る
- **`containers[]` に並べる旧パターンに後戻り**: helm chart の都合などで混在しがち。**新規は initContainers + restartPolicy: Always 一択**

## やること

### 0. 準備

```bash
kubectl create ns ch03-sidecar
kubectl label ns ch03-sidecar pod-security.kubernetes.io/enforce=baseline --overwrite
```

### 1. 旧パターン — Job が永久に終わらないやつ

```yaml
# job-old-pattern.yaml
apiVersion: batch/v1
kind: Job
metadata: {name: old-job, namespace: ch03-sidecar}
spec:
  template:
    spec:
      restartPolicy: Never
      volumes:
        - name: shared
          emptyDir: {}
      containers:
        # main: 5 秒で終わる "仕事"
        - name: main
          image: busybox:1.36
          command:
            - sh
            - -c
            - |
              for i in 1 2 3 4 5; do
                echo "[main] line $i" | tee -a /var/log/app.log
                sleep 1
              done
              echo "[main] done"
          volumeMounts: [{name: shared, mountPath: /var/log}]
        # sidecar: ログを tail し続ける = 永久に終わらない
        - name: tailer
          image: busybox:1.36
          command:
            - sh
            - -c
            - |
              touch /var/log/app.log
              tail -F /var/log/app.log
          volumeMounts: [{name: shared, mountPath: /var/log}]
```

```bash
kubectl apply -f job-old-pattern.yaml
kubectl -n ch03-sidecar get job old-job -w
# COMPLETIONS が 0/1 のまま。永遠に Running
```

別ターミナルで:

```bash
kubectl -n ch03-sidecar get pods
# old-job-xxxxx   1/2 NotReady ...  あるいは Running が続く
# main は Completed (Exit 0)、tailer は Running

kubectl -n ch03-sidecar logs -l job-name=old-job -c tailer --tail=5
```

→ "**main は終わってるのに sidecar が走り続けて Job が完走しない**" の典型形。Ctrl-C で抜けて、Job は消す:

```bash
kubectl -n ch03-sidecar delete job old-job
```

### 2. 新パターン — KEP-753 ネイティブ sidecar

```yaml
# job-native-sidecar.yaml
apiVersion: batch/v1
kind: Job
metadata: {name: new-job, namespace: ch03-sidecar}
spec:
  template:
    spec:
      restartPolicy: Never
      volumes:
        - name: shared
          emptyDir: {}
      initContainers:
        # KEP-753: restartPolicy: Always を付けると "sidecar" 扱い
        - name: tailer
          image: busybox:1.36
          restartPolicy: Always           # ← これが鍵
          command:
            - sh
            - -c
            - |
              touch /var/log/app.log
              tail -F /var/log/app.log
          volumeMounts: [{name: shared, mountPath: /var/log}]
      containers:
        - name: main
          image: busybox:1.36
          command:
            - sh
            - -c
            - |
              for i in 1 2 3 4 5; do
                echo "[main] line $i" | tee -a /var/log/app.log
                sleep 1
              done
              echo "[main] done"
          volumeMounts: [{name: shared, mountPath: /var/log}]
```

```bash
kubectl apply -f job-native-sidecar.yaml
kubectl -n ch03-sidecar get job new-job -w
# 数秒後: COMPLETIONS 1/1, STATUS Complete
```

```bash
kubectl -n ch03-sidecar describe job new-job | tail -15
# State: Complete, Reason: ... main が exit → sidecar も終了
```

→ **main が exit したら kubelet が sidecar に SIGTERM を送り、Pod が Terminated**。
Job が **完走** する。

### 3. 起動順序を観察

`startupProbe` / `command` の時間差で観察できます:

```yaml
# order-demo.yaml
apiVersion: v1
kind: Pod
metadata: {name: order, namespace: ch03-sidecar}
spec:
  restartPolicy: Never
  initContainers:
    - name: setup
      image: busybox:1.36
      command: ["sh","-c","echo [setup] $(date +%T) start; sleep 2; echo [setup] $(date +%T) done"]
    - name: sidecar
      image: busybox:1.36
      restartPolicy: Always
      command: ["sh","-c","echo [sidecar] $(date +%T) start; sleep 1000"]
      startupProbe:
        exec: {command: ["sh","-c","sleep 3; true"]}
        periodSeconds: 1
        failureThreshold: 30
  containers:
    - name: main
      image: busybox:1.36
      command: ["sh","-c","echo [main] $(date +%T) start; sleep 5; echo [main] $(date +%T) done"]
```

```bash
kubectl apply -f order-demo.yaml
kubectl -n ch03-sidecar wait --for=condition=Initialized pod/order --timeout=60s
kubectl -n ch03-sidecar logs order --all-containers --prefix
# 期待:
#  [pod/order/setup]   [setup]   ... start
#  [pod/order/setup]   [setup]   ... done    ← 通常 init 完了
#  [pod/order/sidecar] [sidecar] ... start
#  (startupProbe 通過 = 3秒)
#  [pod/order/main]    [main]    ... start   ← sidecar が "ready" になってから main
#  [pod/order/main]    [main]    ... done
```

> **発見:** "通常の init → sidecar (Always) → main" の順で **起動順序が保証** され、sidecar が **startupProbe で ready** になるまで main が始まらない。Istio や DB proxy で待ち望まれていた挙動。

### 4. 終了順序を観察

```bash
kubectl -n ch03-sidecar delete pod order --grace-period=30
kubectl -n ch03-sidecar get events --sort-by=.lastTimestamp | tail -10
```

→ **main → sidecar の順** で SIGTERM が送られる。順序付きシャットダウン。

### 5. logging sidecar の実用例

```yaml
# logging-deploy.yaml
apiVersion: apps/v1
kind: Deployment
metadata: {name: web, namespace: ch03-sidecar}
spec:
  replicas: 1
  selector: {matchLabels: {app: web}}
  template:
    metadata: {labels: {app: web}}
    spec:
      volumes:
        - name: varlog
          emptyDir: {}
      initContainers:
        - name: log-shipper
          image: busybox:1.36
          restartPolicy: Always
          command:
            - sh
            - -c
            - |
              touch /var/log/access.log
              tail -F /var/log/access.log
          volumeMounts: [{name: varlog, mountPath: /var/log}]
      containers:
        - name: app
          image: busybox:1.36
          command:
            - sh
            - -c
            - |
              while true; do
                echo "$(date +%T) GET /  200" >> /var/log/access.log
                sleep 2
              done
          volumeMounts: [{name: varlog, mountPath: /var/log}]
```

```bash
kubectl apply -f logging-deploy.yaml
kubectl -n ch03-sidecar rollout status deploy/web
kubectl -n ch03-sidecar logs deploy/web -c log-shipper --tail=5
```

→ "**Pod 終了時に log-shipper が flush できる順序**" が保証されるので、**ログの取りこぼしが減る**。

### 6. 後片付け

```bash
kubectl delete ns ch03-sidecar
```

## やってみて気づくこと

- 旧パターンの "**Job が完走しない**" 痛みは、**1 度経験すると忘れない**
- `restartPolicy: Always` を `initContainers[]` に書くだけで意味が **180 度変わる** API 設計の妙
- main → sidecar の **終了順序** が、ログ取りこぼしや connection drain で効いてくる
- service mesh の `holdApplicationUntilProxyStarts` や、Job 用 sidecar kill script、と過去の "工夫" を **読まなくてよくなる** 時代

## 参考

- KEP-753 Sidecar Containers: https://github.com/kubernetes/enhancements/tree/master/keps/sig-node/753-sidecar-containers
- Blog (v1.28 alpha): https://kubernetes.io/blog/2023/08/25/native-sidecar-containers/
- v1.33 release note (GA): https://kubernetes.io/blog/2025/04/23/kubernetes-v1-33-release/
- Sidecar containers docs: https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/
- Istio holdApplicationUntilProxyStarts (旧 work-around): https://istio.io/latest/docs/reference/config/istio.mesh.v1alpha1/
