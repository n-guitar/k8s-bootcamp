# 02 — kubectl とクラスタの「中身」

## ゴール
- kind で 3 ノードのクラスタを起動
- `kubectl` でクラスタと会話する 7 つの基本動詞 (`get` / `describe` / `logs` / `exec` / `apply` / `delete` / `explain`)
- control-plane の 4 コンポーネントが **Pod として** 動いていることを目で見る

---

## 🤔 なぜ必要？ (ストーリー)

> あなたは前章で「1 台 Docker の限界」を体感した。
> - (a) `docker kill` したら復旧しない
> - (b) スケールに別途 LB が要る
> - (c) 設定がイメージに焼き付く
>
> Docker を 5 台に増やしたとき、誰が「どの Docker にどのコンテナを置くか」を決めるのか?
> 設定変更を 5 台に流すのは誰か? あるノードが死んだら、別ノードに移すのは誰か?
>
> **その "誰か" が Kubernetes です。**
>
> 本章では「**誰か**」の **正体 (control-plane の中身) と話し方 (kubectl)** を覚えます。03 章から (a) (b) (c) への "復讐戦" が始まります。

Kubernetes は最低限こういう登場人物で出来ています:

```
+----------+        +----------------+        +-----+
| kubectl  | --->   | kube-apiserver | <----> | etcd|   ← 望む状態を保存
+----------+        +----------------+        +-----+
                          ↑   ↓
                   +---------------+
                   | scheduler     |   ← Pod を Node に割り付ける
                   | ctrl-manager  |   ← reconcile loop の本体
                   +---------------+
                          ↓
                   +---------------+
                   | kubelet       |   ← 各 Node に常駐、コンテナを動かす
                   +---------------+
```

「**kubectl で YAML を投げる → etcd に保存 → controller が見て働く → kubelet が動かす**」。これが大原則。

## ✨ 面白いポイント (設計)

### 1. **control-plane 自体が "Pod" で動く (static Pod)**

kubeadm / kind で立てたクラスタを覗くと、`kube-apiserver` / `etcd` / `kube-scheduler` / `kube-controller-manager` が **`kube-system` namespace の Pod として** 動いている。

> **痺れ所:** k8s が k8s 自身を動かしている (= self-hosted)。
> 厳密には kubelet が `/etc/kubernetes/manifests/*.yaml` を直接読む **"static Pod"** という仕組みで、kube-apiserver が無くてもブートできる。
> "**鶏と卵問題を、kubelet が manifest を直接読むことで解いた**" のが偉い。

### 2. **`kubectl` は API client、それだけ**

`kubectl get pod` の正体は HTTPS リクエスト 1 本:

```
GET /api/v1/namespaces/default/pods HTTP/1.1
Authorization: Bearer <token>
```

`kubectl --v=8` で **生の HTTP** が見える。これに気付くと、API server だけ立ててれば `curl` でも操作できる、という発想に至る。

### 3. **すべてのリソースが同じ API 規約**

```
GET    /apis/<group>/<version>/namespaces/<ns>/<kind>           # list
GET    /apis/<group>/<version>/namespaces/<ns>/<kind>/<name>    # get
POST                                                            # create
PUT                                                             # update
DELETE                                                          # delete
GET    ...?watch=true                                           # watch (long-poll)
```

Pod も Deployment も Service も、CRD で作ったあなた独自リソースも、**全部同じ規約**。だから kubectl / RBAC / audit が全部に効く。

## 😱 あるある罠

- **`kubectl config` を切り替え忘れ**: 本番に `apply` してしまう事故の原因 No.1。`kubectx` / `kubens` / `KUBECONFIG=` を使う
- **default namespace に何でも作る**: namespace は **コストゼロ** なので、必ず用途別に分ける
- **`kubectl edit` でその場編集**: 同じ修正が次回も再現できない。**YAML を git に置く** のが文化
- **`logs` だけで原因究明しようとする**: `describe` の Events セクションを **必ず見る**。kubelet / scheduler 側のエラーはそこに出る

## やること

### 0. kind とは

`kind` (Kubernetes IN Docker) は、**Docker コンテナを Node に見立てて** k8s クラスタを動かすツール。VM が要らない、起動が秒単位、削除が簡単。

### 1. クラスタを起動する

**最短手順** (本リポジトリの `track-0-fundamentals/kind-config.yaml` を使用):

```bash
cd ../  # track-0-fundamentals に戻る
./scripts/up.sh
```

これは内部で `kind create cluster --image kindest/node:v1.33.0 --config kind-config.yaml` を実行し、metrics-server まで入れます。
中身が気になる方は `kind-config.yaml` を覗いてみてください (3 ノード + zone ラベル + extraPortMappings 80/443)。

うまく行ったか確認:
```bash
kubectl cluster-info
kubectl get nodes -o wide
```

> **このクラスタは Track 0 の以降の章 / Track A でもそのまま使い続けます。** この章末で `kind delete` しないでください (= 後片付けはトラック修了後)。

### 2. ノードを見る

```bash
kubectl get nodes -o wide
# NAME                     STATUS   ROLES           AGE  VERSION  ...
# bootcamp-control-plane   Ready    control-plane   ...  v1.33.0  ...
# bootcamp-worker          Ready    <none>          ...  v1.33.0  ...
# bootcamp-worker2         Ready    <none>          ...  v1.33.0  ...
```

### 3. control-plane の "中身" を覗く

```bash
kubectl -n kube-system get pods
# 注目: etcd-..., kube-apiserver-..., kube-controller-manager-..., kube-scheduler-... が動いている
```

Node に入って実物を確認:

```bash
docker exec -it bootcamp-control-plane bash
ls /etc/kubernetes/manifests/
# etcd.yaml  kube-apiserver.yaml  kube-controller-manager.yaml  kube-scheduler.yaml
crictl ps    # ← Docker ではなく containerd を叩く
exit
```

> 4 つの YAML が **静的に置かれているだけ** で control-plane が動いている事実を確認してください。これが static Pod。

### 4. 7 つの基本動詞

```bash
# get
kubectl -n kube-system get pods

# describe (Events を必ず読む)
kubectl -n kube-system describe pod kube-apiserver-bootcamp-control-plane

# logs
kubectl -n kube-system logs kube-apiserver-bootcamp-control-plane | tail

# exec
kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- sh
# (中で) wget -qO- http://kubernetes.default.svc/version

# apply
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: scratch
  labels:
    pod-security.kubernetes.io/enforce: baseline
EOF

# delete
kubectl delete ns scratch

# explain
kubectl explain pod.spec.containers.resources
```

### 5. `kubectl --v=8` で API server との会話を見る

```bash
kubectl --v=8 get pods 2>&1 | grep -E '(GET|POST|PUT|DELETE) http'
```

→ **`kubectl は単なる HTTP client`** であることを目で確認。

### 6. (任意) クラスタを消す手段の確認

**今は消さないでください** (以降の章でも使う) が、いずれ消す時は:

```bash
./scripts/down.sh
# または
kind delete cluster --name bootcamp
```

## やってみて気づくこと

- control-plane は **特殊な存在ではない**。kubelet が読む 4 つの YAML が動いているだけ
- `kubectl` は魔法ではなく、**HTTP/JSON を喋っているクライアント**
- なので、API さえあれば curl でも操作可能 (= 自動化と CI が容易)
- 「kubectl で出来る事しか出来ない」と思いがちだが、逆で **kubectl は表現の 1 つ** に過ぎない

## 参考

- kubectl reference: https://kubernetes.io/docs/reference/kubectl/
- kind: https://kind.sigs.k8s.io/
- static Pod: https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/
