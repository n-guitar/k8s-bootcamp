# 00 — Prerequisites (Track A 入口)

## ゴール
- Track A で使う **docker / kind / kubectl / helm** をローカルに揃える
- バージョン要件 (k8s v1.33 系) を満たす組み合わせを確認
- kind 設定ファイルと起動スクリプトは **Track 0 と共有** することを把握する
- "動く" を 1 コマンドで確かめる (`scripts/up.sh`)

---

## 🤔 なぜ必要？ (ストーリー)

> あなたは「v1.22 以降の変化を追体験するぞ」と勢いよく始めた。
> ところが最初に立ちはだかったのは KEP ではなく **インストールエラー** だった。
>
> - `kind create cluster` → `failed to pull image kindest/node:v1.33.0`。Docker Desktop のリソース枯渇だった。
> - `kubectl apply` → `error: error validating ... server-side apply` で謎の不一致。kubectl v1.22 と server v1.33 で **skew** を 11 マイナー越えていた。
> - `helm install` → `Error: chart requires kubeVersion: >= 1.25` で対応表を見に行く羽目に。
>
> **環境構築でつまずく時間が、k8s 学習の中で一番もったいない**。
> しかも 4 年前の感覚で `docker-for-mac` だけ入れて満足すると、**`crictl` も `cilium-cli` もない** ことに 30 分後に気づく。
>
> この章で **必要ツールを一度だけ全部揃え**、その後の 01〜09 章では「環境のことを忘れて中身に集中する」状態を作ります。

## ✨ 面白いポイント (設計)

### 1. **kind は "Docker の中で k8s を動かす" だけ**

```
host (Mac / Linux / WSL2)
  └─ docker daemon
       └─ container (= kind の "node")  ← この中で kubelet + containerd が動く
            └─ container (= 普通の Pod)
```

> **痺れ所:** "ノード" の正体が **Docker コンテナ 1 個**。だから `docker exec -it bootcamp-control-plane bash` で **「ノードに ssh する代わりに `docker exec`」** ができる。VM を立てる Track B との一番の違い。

### 2. **kind + kubeadm patches で本物のクラスタ挙動を再現**

kind は中で `kubeadm init` を呼んでクラスタを作る。だから:

- AdmissionConfiguration (PSA cluster-wide default) を **kubeadm patches** で差し込める (02 章で使う)
- containerd / CRI / cgroupv2 のスタックは **本物と同じ**
- 学んだ知識が Track B / Track C の vanilla kubeadm / EKS にそのまま転用できる

### 3. **設定とスクリプトは Track 0 と完全共有**

`kind-config.yaml` も `scripts/up.sh` も Track 0 と同じものを使う:

```
../track-0-fundamentals/kind-config.yaml      # 3-node, 80/443 portMapping
../track-0-fundamentals/scripts/up.sh         # 1 コマンド起動
../track-0-fundamentals/scripts/down.sh
```

> **痺れ所:** **同じクラスタを Track 0 → Track A と通しで使える**。「Track A 用にもう 1 個 cluster を作る」みたいなことは要らない。

## 😱 あるある罠

- **kubectl のメジャー skew**: kubectl と apiserver の差は **±1 minor 以内** が公式サポート。古い kubectl のままだと `kubectl debug` や PSA 周りの挙動が違う
- **Docker Desktop のメモリ不足**: CPU 4+ / Memory 8GB+ にしないと Cilium / Argo CD が **OOMKilled** で踊る
- **kind v0.22 以下**: v1.33 ノードイメージに対応していない。`kind --version` で必ず確認
- **WSL2 で `--net=host`**: Linux host と挙動が違う罠多数。WSL2 では Docker Desktop の WSL2 統合を有効化推奨
- **Apple Silicon で amd64-only image**: 一部 CRD 同梱 image が arm64 未対応のことがある。`--platform linux/amd64` を必要に応じて

## やること

### 0. 何が必要かの一覧

| ツール | バージョン | 用途 |
|---|---|---|
| Docker | 24+ | kind の土台 |
| kind | v0.23+ | kindest/node:v1.33 を扱えること |
| kubectl | v1.32 〜 v1.34 | server v1.33 と skew ±1 以内 |
| helm | v3.14+ | Envoy Gateway / Argo CD / cosign 系 chart |
| (任意) cilium-cli | v0.16+ | 06 章 |
| (任意) cosign | v2.4+ | 09 章 |

### 1. OS 別インストール

#### macOS (Homebrew)

```bash
# Docker は Docker Desktop / Colima / Rancher Desktop のいずれか
brew install --cask docker        # or: brew install colima docker

brew install kind kubectl helm
brew install cilium-cli cosign    # 任意 (06, 09 章用)
```

Colima を使う場合は CPU / Memory を増やす:

```bash
colima start --cpu 4 --memory 8 --disk 40
```

#### Linux (Debian / Ubuntu)

```bash
# Docker engine
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER"   # 再ログインで反映

# kind
curl -Lo /tmp/kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64
sudo install -m 0755 /tmp/kind /usr/local/bin/kind

# kubectl
curl -LO "https://dl.k8s.io/release/v1.33.0/bin/linux/amd64/kubectl"
sudo install -m 0755 kubectl /usr/local/bin/kubectl

# helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

#### Windows (WSL2)

WSL2 Ubuntu の中で上記 Linux と同じ手順。Docker Desktop の Settings → Resources → WSL Integration で対象ディストロを有効化しておく。

### 2. 入った? を確認

```bash
docker version --format '{{.Server.Version}}'
kind --version
kubectl version --client=true
helm version --short
```

期待する出力例:

```
27.0.3
kind v0.23.0 go1.21.10 darwin/arm64
Client Version: v1.33.0
v3.14.4+g81c902a
```

### 3. Docker のリソース確認

```bash
docker info --format '{{.NCPU}} CPUs / {{.MemTotal}} bytes'
# 期待: 4 CPUs 以上、8 GiB 以上
```

足りなければ Docker Desktop / Colima の設定を引き上げる。

### 4. Track 0 と共有のクラスタ設定を確認

このトラックでは Track 0 と **同じ kind-config / 同じ scripts** を使います。
ファイルの実体はこちら:

```bash
ls -l ../track-0-fundamentals/kind-config.yaml
ls -l ../track-0-fundamentals/scripts/up.sh
ls -l ../track-0-fundamentals/scripts/down.sh
```

中身は 3-node (control-plane×1 + worker×2)、host の 80/443 を抜き、Worker に `topology.kubernetes.io/zone` ラベルが付く構成です。詳細は次章 01 で読みます。

### 5. 動作確認 (= "Hello kind")

01 章で本番の起動をしますが、ここでは **試し起動 → 即破棄** で道具一式が揃っていることだけ確認:

```bash
cd ../track-0-fundamentals
./scripts/up.sh v1.33.0
kubectl get nodes -o wide
# 期待: control-plane + worker×2 が Ready

./scripts/down.sh   # 一旦消す。本番は 01 章で
```

`up.sh` が "ok: docker", "ok: kind", "ok: kubectl" と緑で並べば Track A の入口は通過です。

### 6. 後片付け

この章はインストール確認なので削除するリソースはありません。クラスタを試し起動した場合は `./scripts/down.sh` で消えています。

## やってみて気づくこと

- "**ノード = Docker コンテナ**" という事実が、その後の `docker exec` でのデバッグ手段の発想を変える
- `scripts/up.sh` が "前提ツール check → cluster 起動 → metrics-server 投入" を **1 コマンドにまとめる** ありがたみ
- 同じ `kind-config.yaml` で Track 0 の章 (Pod / Deployment / Gateway) を回した後、続けて Track A で v1.33 新機能を試せる **連続性**
- kubectl の skew 制約は **±1 minor**。これを越えると `kubectl apply` の細かい挙動が壊れることがある

## 参考

- kind release notes: https://github.com/kubernetes-sigs/kind/releases
- kubectl install: https://kubernetes.io/docs/tasks/tools/
- helm install: https://helm.sh/docs/intro/install/
- cilium-cli: https://github.com/cilium/cilium-cli
- cosign install: https://docs.sigstore.dev/cosign/system_config/installation/
- Version skew policy: https://kubernetes.io/releases/version-skew-policy/
