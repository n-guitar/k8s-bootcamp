#!/usr/bin/env bash
# Track B 03: Cilium v1.16 を helm でインストール
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CH_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_DIR="$(cd "$CH_DIR/../01-terraform-vpc-ec2/terraform" && pwd)"
export KUBECONFIG="${KUBECONFIG:-$CH_DIR/../02-kubeadm-bootstrap/kubeconfig}"

CP_PRIVATE=$(terraform -chdir="$TF_DIR" output -raw cp_private_ip)
echo "CP_PRIVATE=$CP_PRIVATE"

helm repo add cilium https://helm.cilium.io/ >/dev/null
helm repo update >/dev/null

sed "s/__CP_PRIVATE__/${CP_PRIVATE}/g" "$CH_DIR/manifests/cilium-values.yaml" > /tmp/cilium-values.yaml

helm upgrade --install cilium cilium/cilium \
  --version 1.16.5 \
  --namespace kube-system \
  --values /tmp/cilium-values.yaml

kubectl -n kube-system rollout status ds/cilium --timeout=5m
kubectl get nodes -o wide
