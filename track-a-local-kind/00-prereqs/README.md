# 00 — Prerequisites

## ゴール
ローカルマシンに必要なツール一式をインストールし、`docker` / `kubectl` / `kind` が動くことを確認する。

## 必須ツール
- Docker (24+) — Docker Desktop / Colima / Rancher Desktop いずれも可
- kind (v0.23+)
- kubectl (v1.33.x)
- helm (v3.14+)
- cilium-cli (v0.16+)
- cosign (v2.4+)
- (任意) `crictl` — Node 内で実行するためのクライアント

## TODO
- [ ] OS 別インストール手順 (mac / linux / wsl2)
- [ ] バージョン確認スクリプト `scripts/check-versions.sh`
- [ ] Docker Desktop の resource 設定 (CPU 4+, Mem 8GB+) のスクショ

## 参考
- kind release notes: https://github.com/kubernetes-sigs/kind/releases
- kubectl install: https://kubernetes.io/docs/tasks/tools/
