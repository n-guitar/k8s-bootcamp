#!/usr/bin/env bash
# 1コマンドでクラスタ起動。Track 0 / Track A 共通の入口。
#
# 何をするか:
#   1. docker / kind / kubectl の存在確認
#   2. kind クラスタ "bootcamp" を起動 (既にあればスキップ)
#   3. zone ラベルが Worker に付いていることを確認
#   4. metrics-server を入れる (kubectl top で楽しくなる)
#
# 使い方: ./scripts/up.sh [k8s-version]
#   例:   ./scripts/up.sh                  # v1.33.0
#         ./scripts/up.sh v1.32.0
set -euo pipefail

K8S_VERSION="${1:-v1.33.0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$(cd "$SCRIPT_DIR/.." && pwd)/kind-config.yaml"

cyan()   { printf "\033[1;36m%s\033[0m\n" "$*"; }
green()  { printf "\033[1;32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[1;33m%s\033[0m\n" "$*"; }
red()    { printf "\033[1;31m%s\033[0m\n" "$*" >&2; }

# --- 1. 前提ツール確認 ---
cyan "==> 前提ツールチェック"
for cmd in docker kind kubectl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    red "missing: $cmd"
    red "  PREREQUISITES.md を参照してインストールしてください"
    exit 1
  fi
  green "  ok: $cmd ($($cmd --version 2>&1 | head -1))"
done

if ! docker info >/dev/null 2>&1; then
  red "docker daemon が動いていません。Docker Desktop / Colima を起動してください"
  exit 1
fi

# --- 2. クラスタ起動 ---
cyan "==> kind クラスタ 'bootcamp' を起動 (image: kindest/node:${K8S_VERSION})"
if kind get clusters 2>/dev/null | grep -qx bootcamp; then
  yellow "  既に 'bootcamp' クラスタが存在します。再利用します"
else
  kind create cluster \
    --name bootcamp \
    --image "kindest/node:${K8S_VERSION}" \
    --config "$CONFIG_FILE" \
    --wait 120s
fi

# --- 3. Node の sanity check ---
cyan "==> Node の状態確認"
kubectl get nodes -o wide

# --- 4. metrics-server (kubectl top を使えるように) ---
cyan "==> metrics-server をインストール (kind 向け --kubelet-insecure-tls 付き)"
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl -n kube-system patch deployment metrics-server --type=json -p='[
  {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}
]' 2>/dev/null || true
kubectl -n kube-system rollout status deployment metrics-server --timeout=120s || true

green ""
green "==================================================================="
green " 準備完了!"
green ""
green "  クラスタ: bootcamp"
green "  Pod 状態: kubectl get pods -A"
green "  停止: ./scripts/down.sh"
green "==================================================================="
