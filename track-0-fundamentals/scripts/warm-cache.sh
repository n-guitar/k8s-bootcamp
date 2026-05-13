#!/usr/bin/env bash
# Track 0 で使う全 image を docker pull + kind load する。
# 飛行機・出張など "ネット無し環境" で進めたい時の事前準備。
#
# 想定所要時間: 初回 5〜10 分 (約 500MB ダウンロード)
# 2 回目以降: 1 分以内 (= kind load のみ)
#
# 使い方:
#   ./scripts/up.sh          # 先にクラスタを立てておく
#   ./scripts/warm-cache.sh  # これを実行
#
# 後はオフラインでも Track 0 の各章 / 10-mini-app が動きます。
set -euo pipefail

CLUSTER="${CLUSTER:-bootcamp}"

# Track 0 全章 + mini-app で使う image 一覧
IMAGES=(
  # ch01 / ch03 / ch04 / ch07 / ch08 / mini-app
  "nginx:1.27"
  "nginx:1.27-alpine"
  "nginx:1.28"
  "nginxinc/nginx-unprivileged:1.27-alpine"
  "busybox:1.36"
  "curlimages/curl:8.10.1"
  # ch04 / ch08 のデモ
  "nginxdemos/hello:plain-text"
  "hashicorp/http-echo:1.0.0"
  # ch06 / ch10 の DB
  "postgres:16-alpine"
  # ch10 の Python AP は手元 build なので含めない
)

cyan()  { printf "\033[1;36m%s\033[0m\n" "$*"; }
green() { printf "\033[1;32m%s\033[0m\n" "$*"; }
red()   { printf "\033[1;31m%s\033[0m\n" "$*" >&2; }

if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  red "kind クラスタ '$CLUSTER' が無い。先に ./scripts/up.sh を実行してください。"
  exit 1
fi

cyan "==> docker pull (キャッシュ済みならスキップされます)"
for img in "${IMAGES[@]}"; do
  echo "    pulling $img ..."
  docker pull --quiet "$img" >/dev/null
done

cyan "==> kind load (全 image をクラスタ Node に流し込む)"
for img in "${IMAGES[@]}"; do
  echo "    loading $img into $CLUSTER ..."
  kind load docker-image "$img" --name "$CLUSTER"
done

# Envoy Gateway 関連も pull しておく (helm が pull するイメージ)
cyan "==> Envoy Gateway / Gateway API 用 image を pull"
EG_IMAGES=(
  "docker.io/envoyproxy/gateway:v1.1.0"
  "docker.io/envoyproxy/envoy:distroless-v1.31.0"
)
for img in "${EG_IMAGES[@]}"; do
  docker pull --quiet "$img" >/dev/null 2>&1 || echo "    skip $img (private or rate-limited)"
  kind load docker-image "$img" --name "$CLUSTER" 2>/dev/null || true
done

green ""
green "==================================================================="
green "  warm cache 完了。これでオフラインでも Track 0 が進められます。"
green "  (注: helm install の chart 本体は別途キャッシュが必要)"
green "==================================================================="
