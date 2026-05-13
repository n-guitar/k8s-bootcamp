# 01 — Cluster Up (kind multi-node + crictl + registry.k8s.io)

## ゴール
- Track 0 と共有の `kind-config.yaml` で **control-plane × 1 / worker × 2** を起動
- ノード内に **`docker exec`** で入って **containerd / `crictl`** を体験 (dockershim 削除後のデファクト)
- システム Pod のイメージが **`registry.k8s.io`** 由来である事 (旧 `k8s.gcr.io` ではない) を確認

---

## 🤔 なぜ必要？ (ストーリー)

> 4 年ぶりにクラスタに入ったあなたは、まず `docker ps` を Node 上で打って `kubelet` 配下のコンテナを覗こうとした。
> → `docker: command not found`。
> 「あれ、ノードに Docker が居ない…?」
>
> 同僚:「v1.24 で **dockershim 削除** ですよ。kubelet は containerd と CRI 経由で喋ってます。`crictl ps` を使ってください」
>
> 別の同僚:「あと `k8s.gcr.io` のイメージは引けなくなりました。**`registry.k8s.io`** に揃えてください。古い書籍の `image: k8s.gcr.io/...` を `kubectl apply` しても、ノードによっては **ImagePullBackOff** で 5 分溶けます」
>
> 「**ノードの中身が変わった**」のに、上のレイヤ (kubectl / YAML) はほとんど同じ顔をしている。だから油断する。
> この章では、**ノードに `docker exec` で入って中の世界を覗く** ことで、その変化を体に入れます。

## ✨ 面白いポイント (設計)

### 1. **CRI = "kubelet とランタイムの間の標準語"**

```
kubelet  ──(CRI: gRPC)──>  containerd  ──>  runc / containerd-shim
                            │
                       crictl も同じ CRI を叩く
```

- v1.24 で dockershim 削除 → kubelet は **CRI しか喋らない**
- containerd / CRI-O / その他は **CRI を実装する側**
- `crictl` は kubelet と **同じ口** を叩くデバッグ用 CLI

> **痺れ所:** 「kubelet 専用の Docker 直結コード」を捨て、**抽象を 1 枚** はさんだだけで、ランタイム差し替えがコスト無しになった。Cilium も Wasm runtime も Kata Containers も、この抽象の上で動く。

### 2. **`crictl` は "Pod" を知っているが "Deployment" は知らない**

```
docker ps  → "コンテナ" の世界
crictl ps  → "コンテナ" の世界 + "Pod (sandbox)" の概念あり
kubectl    → "Deployment / Service" など宣言的世界
```

`crictl pods` という独自コマンドがある。これは **k8s より下、Docker より上** という絶妙なレイヤ。

### 3. **registry.k8s.io への移行 (KEP-3937)**

旧 `k8s.gcr.io` は **Google が金を払い続けるしかなく、コミュニティで管理できない**。
2022/4 に `registry.k8s.io` が立ち、複数 CDN にフェイルオーバする community-owned ミラーに。
2023/4 に `k8s.gcr.io` は **freeze**。新しいイメージは push されない。

> **痺れ所:** 古いマニフェストを救うために `k8s.gcr.io` から `registry.k8s.io` への **redirector** が立っている。とはいえ "永久" ではない。"イメージレジストリ自体を CNCF 文化に合わせる" 大きな例。

## 😱 あるある罠

- **ノードで `docker ps` を打つ**: kind ノードに docker はいない (kind のホスト側に居る Docker と混同しがち)。`crictl ps` を使う
- **`k8s.gcr.io/...` のマニフェスト**: 古いブログ / 書籍コピペで持ち込むと将来引けなくなる
- **`crictl` の設定漏れ**: `endpoint` が指定されていないと "no runtime found" と言われる。kind ノード内はデフォルトで通る
- **kind の Pod IP を host から叩こうとする**: kind の Pod 網は host から直接見えない。host から到達するには `extraPortMappings` か `kubectl port-forward`
- **`kind create cluster` を毎回打って汚す**: 既存クラスタを忘れると複数並ぶ。`kind get clusters` で確認

## やること

### 0. 準備

クラスタ起動は Track 0 共有のスクリプトに任せます。

```bash
cd /path/to/k8s-bootcamp
ls track-0-fundamentals/kind-config.yaml      # 中身を眺めるなら less で
```

### 1. multi-node kind クラスタ起動

```bash
cd track-0-fundamentals
./scripts/up.sh v1.33.0
```

中で何が起きているか:

1. `docker info` で daemon を確認
2. `kind create cluster --image kindest/node:v1.33.0 --config kind-config.yaml`
   - control-plane × 1, worker × 2
   - control-plane に `extraPortMappings: 80→80, 443→443` (04 章で使う)
   - Worker に `topology.kubernetes.io/zone=za` / `zb`
3. `metrics-server` を投入 (`kubectl top` を使えるように)

確認:

```bash
kubectl get nodes -o wide
# bootcamp-control-plane     Ready    control-plane   ...   v1.33.0
# bootcamp-worker            Ready    <none>          ...   v1.33.0
# bootcamp-worker2           Ready    <none>          ...   v1.33.0

kubectl get nodes -L topology.kubernetes.io/zone
# worker / worker2 に za / zb のラベルが付いていること
```

### 2. ノードに `docker exec` で入る

```bash
docker ps --filter "label=io.x-k8s.kind.cluster=bootcamp"
# bootcamp-control-plane / bootcamp-worker / bootcamp-worker2 の 3 つが見える

docker exec -it bootcamp-control-plane bash
# ノード(= Docker コンテナ)の中に居る状態
```

中に入ったら:

```bash
# kubelet と containerd のプロセス
ps -ef | grep -E 'kubelet|containerd' | grep -v grep

# docker は居ない
which docker || echo "no docker here (dockershim is gone)"

# でも crictl は居る
crictl --version
```

### 3. `crictl` で Pod / コンテナを覗く

ノード内で:

```bash
# Pod sandbox 一覧 (= kubelet が k8s から指示された "Pod" 単位)
crictl pods

# その下のコンテナ一覧 (= sidecar も別行で出る)
crictl ps

# kubelet と containerd の通信先
crictl info | head -20

# あるコンテナの logs / inspect (id は crictl ps の左列)
crictl logs <CONTAINER_ID> 2>&1 | tail -5
crictl inspect <CONTAINER_ID> | head -40
```

> **発見:** `crictl ps` の出力は `kubectl get pods -A -o wide` で見える Pod と **1:1 対応** している。ただし `Deployment` や `Namespace` の概念は無い。**「下のレイヤ」** から見える k8s。

ノードから抜ける:

```bash
exit
```

### 4. システム Pod のイメージが `registry.k8s.io` 由来か確認

```bash
kubectl get pods -A -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' \
  | sort -u
```

出力例:

```
registry.k8s.io/coredns/coredns:v1.11.1
registry.k8s.io/etcd:3.5.12-0
registry.k8s.io/kube-apiserver:v1.33.0
registry.k8s.io/kube-controller-manager:v1.33.0
registry.k8s.io/kube-proxy:v1.33.0
registry.k8s.io/kube-scheduler:v1.33.0
registry.k8s.io/metrics-server/metrics-server:v0.7.2
```

→ **`k8s.gcr.io` が出てこない** こと、これが v1.27 以降のデフォルト。

```bash
# 念のため "k8s.gcr.io" を含む image が無いことを確認
kubectl get pods -A -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' \
  | grep 'k8s.gcr.io' || echo "OK: no legacy k8s.gcr.io image"
```

### 5. `docker` と `crictl` の対応表 (覚え書き)

| やりたいこと | Docker (旧) | crictl (新, ノード内) | kubectl (上から) |
|---|---|---|---|
| コンテナ一覧 | `docker ps` | `crictl ps` | `kubectl get pods -A` |
| Pod 一覧 | (無い) | `crictl pods` | `kubectl get pods -A` |
| ログ | `docker logs ID` | `crictl logs ID` | `kubectl logs POD` |
| シェル | `docker exec -it ID sh` | `crictl exec -it ID sh` | `kubectl exec -it POD -- sh` |
| イメージ一覧 | `docker images` | `crictl images` | (無し) |
| 削除 | `docker rm ID` | `crictl rm ID` | `kubectl delete pod POD` |

ノードで `crictl` を使うのは **障害解析のとき**。普段の運用は `kubectl` で十分。

### 6. 後片付け (= この章では残しておく)

このクラスタは以降の章 (02〜04) で使い続けるので **削除しません**。
完全に終わるときだけ:

```bash
cd ../track-0-fundamentals
./scripts/down.sh
```

## やってみて気づくこと

- ノードに **docker が居ない** ことを目で見た瞬間、dockershim 撤廃が "概念" から "事実" になる
- `crictl pods` と `kubectl get pods` で **見ているレイヤが違う** が、対象は同じであるという二重構造
- `kind` ノードに `docker exec` で入れる手軽さは、トラブルシュート学習の最高の砂場
- `registry.k8s.io` への移行は、image レジストリという "縁の下" まで CNCF / community owned になった象徴

## 参考

- dockershim removal FAQ: https://kubernetes.io/blog/2022/02/17/dockershim-faq/
- KEP-2221 (CRI standardization): https://github.com/kubernetes/enhancements/tree/master/keps/sig-node/2221-cri-as-standard-interface
- crictl: https://kubernetes.io/docs/tasks/debug/debug-cluster/crictl/
- registry.k8s.io 移行: https://kubernetes.io/blog/2023/03/10/image-registry-redirect/
- kind: https://kind.sigs.k8s.io/
