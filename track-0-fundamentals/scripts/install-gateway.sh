#!/usr/bin/env bash
# Envoy Gateway を入れる。Track 0 ch08 と ch10 で必要。
# helm が無い場合は brew/apt で入れて、と案内する。
set -euo pipefail

cyan()  { printf "\033[1;36m%s\033[0m\n" "$*"; }
green() { printf "\033[1;32m%s\033[0m\n" "$*"; }
red()   { printf "\033[1;31m%s\033[0m\n" "$*" >&2; }

if ! command -v helm >/dev/null 2>&1; then
  red "helm が必要です。PREREQUISITES.md を参照して入れてください。"
  exit 1
fi

GW_API_VERSION="${GW_API_VERSION:-v1.1.0}"
EG_VERSION="${EG_VERSION:-v1.1.0}"

cyan "==> Gateway API CRD を install (${GW_API_VERSION})"
kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GW_API_VERSION}/standard-install.yaml"

cyan "==> Envoy Gateway を helm install (${EG_VERSION})"
helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm \
  --version "${EG_VERSION}" \
  -n envoy-gateway-system --create-namespace \
  --wait

cyan "==> envoy-gateway-system の Pod 状態"
kubectl -n envoy-gateway-system get pods

green ""
green "Gateway API 準備完了"
green "  GatewayClass: kubectl get gatewayclass"
green "  使い方: 各 namespace で Gateway + HTTPRoute を作成"
