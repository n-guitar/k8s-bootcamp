#!/usr/bin/env bash
# 環境チェック + クラスタの健康診断。困ったら最初に叩く。
set -uo pipefail

ok()   { printf "  \033[1;32m✓\033[0m %s\n" "$*"; }
ng()   { printf "  \033[1;31m✗\033[0m %s\n" "$*"; }
warn() { printf "  \033[1;33m!\033[0m %s\n" "$*"; }

echo "== 前提ツール =="
for cmd in docker kind kubectl helm make curl jq; do
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$cmd: $($cmd --version 2>&1 | head -1)"
  else
    case "$cmd" in
      jq)   warn "$cmd: 未インストール (make smoke で pretty print されない、致命でない)";;
      helm) warn "$cmd: 未インストール (08 章 Gateway / install-gateway.sh で必要)";;
      make) warn "$cmd: 未インストール (10 章 mini-app の make up が動かない)";;
      *)    ng   "$cmd: 未インストール";;
    esac
  fi
done

echo ""
echo "== Docker daemon =="
if docker info >/dev/null 2>&1; then
  ok "docker daemon 動作中"
else
  ng "docker daemon が起動していません"
  exit 1
fi

echo ""
echo "== kind クラスタ =="
if kind get clusters 2>/dev/null | grep -qx bootcamp; then
  ok "クラスタ 'bootcamp' が存在"
else
  ng "クラスタ 'bootcamp' が存在しません。./scripts/up.sh を実行してください"
  exit 1
fi

echo ""
echo "== kubectl 接続 =="
if kubectl cluster-info >/dev/null 2>&1; then
  ok "kubectl で control-plane に到達"
else
  ng "kubectl が control-plane に到達できません"
  exit 1
fi

echo ""
echo "== Node 状態 =="
kubectl get nodes -o wide

echo ""
echo "== kube-system Pods =="
kubectl -n kube-system get pods

echo ""
echo "== 使い回し可能な NS (label 済) =="
kubectl get ns -L pod-security.kubernetes.io/enforce
