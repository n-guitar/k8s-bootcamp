#!/usr/bin/env bash
# Track B 00-prereqs: ツール / AWS 認証の事前チェック
set -euo pipefail

echo "==== versions ===="
aws --version
terraform version | head -1
kubectl version --client | head -2 || true
helm version --short
cilium version --client || true
jq --version || echo "(jq optional)"

echo
echo "==== AWS identity ===="
aws sts get-caller-identity

echo
echo "==== Region ===="
echo "AWS_REGION=${AWS_REGION:-unset}"
echo "AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-unset}"
