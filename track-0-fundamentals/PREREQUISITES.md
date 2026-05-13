# 前提ツールのインストール

Track 0 / Track A を進めるのに必要なものはこれだけ。**5 分で揃います。**

## 必須

| ツール | 役割 | これが無いと… |
|---|---|---|
| **Docker** | コンテナランタイム、kind が中で使う | そもそも何も動かない |
| **kind** | kubernetes-in-docker | クラスタが立たない |
| **kubectl** | k8s の CLI | クラスタと話せない |
| **make** | 10 章 (mini-app) で `make up / smoke` を使う | mini-app の 1 コマンド起動が出来ない (= 手で apply は可能) |
| **helm** | 08 章 (Gateway) で Envoy Gateway を install | install-gateway.sh が動かない |

## あると楽しい

| ツール | 役割 | 章 |
|---|---|---|
| **jq** | JSON 整形 | 全般 (kubectl の `-o json` / `make smoke` で pretty print) |
| **curl** | HTTP クライアント | 04, 08, 10 |
| **stern** (推奨) | 複数 Pod のログを並行 tail | 全般 |

---

## macOS (Homebrew)

```bash
brew install --cask docker     # Docker Desktop。起動して daemon を ready に
brew install kind kubectl helm jq stern
```

> Docker Desktop の代わりに `colima` (`brew install colima` → `colima start --cpu 4 --memory 6`) も可。商用ライセンスを避けたい場合の選択肢。

## Linux (Ubuntu / Debian 系)

```bash
# Docker
sudo apt update && sudo apt install -y docker.io
sudo usermod -aG docker $USER && newgrp docker

# kubectl (本リポジトリは v1.33.0 を想定。skew を避けるため明示バージョンを推奨)
KVER=v1.33.0
curl -LO "https://dl.k8s.io/release/${KVER}/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# kind
[ "$(uname -m)" = "x86_64" ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64
[ "$(uname -m)" = "aarch64" ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-arm64
chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind

# helm / jq / stern
sudo apt install -y jq
curl https://baltocdn.com/helm/signing.asc | sudo gpg --dearmor -o /usr/share/keyrings/helm.gpg
echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt update && sudo apt install -y helm
```

## Windows (WSL2 推奨)

WSL2 (Ubuntu) を立てて、その中で **Linux と同じ手順** をやるのが一番楽です。
Docker Desktop の WSL backend を有効化しておくと、wsl 内の `docker` がそのまま使えます。

---

## 動作確認

```bash
./scripts/doctor.sh
```

すべて緑 (✓) なら、`./scripts/up.sh` でクラスタを起動できます。

## リソース目安

kind の 3 ノードクラスタを動かすために、Docker に **CPU 4 / メモリ 6GB** 程度は割り当てておいてください。
Docker Desktop の場合は Settings > Resources から。
