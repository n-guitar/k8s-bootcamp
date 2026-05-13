# 05 — ConfigMap と Secret

## ゴール
- アプリの **設定** をイメージから分離する基本
- ConfigMap / Secret を **環境変数** と **ファイルマウント** で注入する違い
- "Secret" の限界 (= 単なる base64) と、外部 Secret 管理への伏線

---

## 🤔 なぜ必要？ (ストーリー)

> あなたは `myapp:0.1` というイメージを作った。中に `app.conf` を `COPY` してある。
> staging と本番で設定が違う。
> → "**設定だけ違う 2 つのイメージ**" を作ることに?
> → タグ管理地獄。staging だけ反映済みなのに本番だけ古い、みたいな事故。
>
> 同じ問題は DB のパスワードでも起きる。**パスワードがイメージに焼き込まれる**?
> docker push したら誰でも履歴から拾える。Git に push したら…?
>
> 「**設定値はイメージから外し、起動時に注入する**」
> これを実現するのが **ConfigMap** (普通の値) と **Secret** (機密値)。

## ✨ 面白いポイント (設計)

### 1. **同じインターフェース、別の意味**

ConfigMap と Secret は **YAML の構造がほぼ同じ**。Pod から見ても同じく env / volume として注入できる。
違いは:

| | ConfigMap | Secret |
|---|---|---|
| 用途 | 普通の設定 | 機密値 |
| 保存 | etcd に **平文** | etcd に base64 (= 平文同等) → 別途 KMS で encryption at rest |
| API | `core/v1` | `core/v1`、type 別 (`Opaque`, `tls`, `dockerconfigjson`, ...) |
| 表示 | `kubectl get cm <name> -o yaml` で見える | `kubectl get secret <name> -o yaml` で base64、デフォルトでは要 RBAC |

> **痺れ所:** インターフェースを揃えたので、**Pod 側は "config か secret か" を意識せずに済む** (env / volume として同じ書き方)。

### 2. **ファイルマウントは "**自動更新**" される**

ConfigMap / Secret を **volume として** マウントすると、内容を更新したら数十秒以内に Pod 内のファイルも自動で書き換わる (kubelet が watch している)。

> **痺れ所:** アプリ側が「ファイル変更を検知して reload」するように書けば、**Pod 再起動なしで設定変更** が出来る。これは env 注入では出来ない (env はプロセス起動時に固定)。

### 3. **`subPath` の罠と仕様**

特定ファイルだけマウントしたい時 `subPath: app.conf` を使えるが、**subPath を使うと自動更新されない**。これは「subPath は実体ではなく、ファイル参照のコピーを作る」設計上の制約。

### 4. **Secret は "**機密**" だけど "**暗号化**" ではない**

`kubectl create secret generic` の base64 は **エンコーディング** であって暗号化ではない。
本当に守るには:
- etcd encryption at rest (KMS v2) ← Track B/C で
- External Secrets Operator (AWS Secrets Manager / Vault) で「**etcd には書かない**」
- Sealed Secrets (Bitnami) で「Git に書けるよう公開鍵暗号化」

> **痺れ所:** "k8s 標準 Secret は通常の YAML と同じく etcd に書かれる" という割り切り。
> その上で、**外部に置く** という選択肢を Operator で広げているのが現代的。

## 😱 あるある罠

- **env 注入したのに設定が変わらない**: env は起動時固定。**volume マウント** に変えるか、Pod を再起動 (`kubectl rollout restart`)
- **base64 を暗号化と誤解**: Secret を git に commit して大事故、というのが本当に多い
- **immutable: true を知らずに `kubectl edit`**: hot reload を防げるが、変更時は **作り直し** が必要
- **`subPath` で全部設定**: 自動更新が効かない罠。`mountPath` で全部 mount → アプリ側に必要なファイル指定が無難

## やること

### 0. 準備

```bash
kubectl create ns ch05 --dry-run=client -o yaml | kubectl apply -f -
kubectl label ns ch05 pod-security.kubernetes.io/enforce=baseline --overwrite
# ↑ baseline ラベルは「Pod の特権昇格を防ぐ標準のガード」。09 章で詳説。今は "本番想定の最低ライン" と覚えて進めて OK。
```

### 1. ConfigMap を 2 通りで作る

#### YAML から
```yaml
# cm.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: web-config
  namespace: ch05
data:
  GREETING: "hello from configmap"
  app.conf: |
    server_name = web
    log_level = info
```

```bash
kubectl apply -f cm.yaml
```

#### `kubectl create` で
```bash
kubectl -n ch05 create configmap web-config2 \
  --from-literal=GREETING2='hi' \
  --from-file=./app.conf
```

### 2. Secret を作る

```bash
kubectl -n ch05 create secret generic db-cred \
  --from-literal=DB_USER=app \
  --from-literal=DB_PASSWORD='s3cret!'
kubectl -n ch05 get secret db-cred -o yaml | head
# → data: は base64
```

### 3. 環境変数として注入 (= 起動時固定)

```yaml
# pod-env.yaml
apiVersion: v1
kind: Pod
metadata:
  name: env-demo
  namespace: ch05
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "echo G=$GREETING U=$DB_USER P=$DB_PASSWORD; sleep 3600"]
      env:
        - name: GREETING
          valueFrom:
            configMapKeyRef: {name: web-config, key: GREETING}
        - name: DB_USER
          valueFrom:
            secretKeyRef: {name: db-cred, key: DB_USER}
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef: {name: db-cred, key: DB_PASSWORD}
```

```bash
kubectl apply -f pod-env.yaml
kubectl -n ch05 logs env-demo
# → G=hello from configmap U=app P=s3cret!
```

### 4. ファイルとしてマウント (= 自動更新あり)

```yaml
# pod-vol.yaml
apiVersion: v1
kind: Pod
metadata:
  name: vol-demo
  namespace: ch05
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "while true; do echo '---'; cat /etc/app/app.conf; sleep 5; done"]
      volumeMounts:
        - name: cfg
          mountPath: /etc/app
  volumes:
    - name: cfg
      configMap:
        name: web-config
```

```bash
kubectl apply -f pod-vol.yaml
kubectl -n ch05 logs -f vol-demo &
```

別ターミナルで `kubectl edit` するか、コピペで動く `kubectl patch` で書き換え:

```bash
# 対話で書き換え (Vim 等が開く)
kubectl -n ch05 edit cm web-config

# または 1 行で
kubectl -n ch05 patch cm web-config --type merge -p '{
  "data": {"app.conf": "server_name = web\nlog_level = debug\n"}
}'
```

→ 数十秒後、`vol-demo` の log にも **新しい内容** が現れる。**Pod 再起動なし!**

### 5. immutable Secret / ConfigMap

```yaml
# (cm.yaml に追記)
immutable: true
```

→ 以降この CM は変更不可。誤上書き防止。変更したい時は新名前で作る。

### 6. 後片付け

```bash
kubectl delete ns ch05
```

## やってみて気づくこと

- **env 注入は便利だが固定**。設定変更を反映したいなら **volume マウント**
- **Secret は base64 にすぎない**。本当に守りたいなら外部 Secret 管理を併用
- ConfigMap も Secret も「**Pod 側は使い方が同じ**」: env か volume の 2 通りのみ
- **`kubectl rollout restart deploy/<name>`** が、env 注入の Pod に変更を反映する一番素直な手段

## 参考

- ConfigMap: https://kubernetes.io/docs/concepts/configuration/configmap/
- Secret: https://kubernetes.io/docs/concepts/configuration/secret/
- 設定変更ベストプラクティス: https://kubernetes.io/docs/concepts/configuration/overview/
- External Secrets Operator: https://external-secrets.io/
