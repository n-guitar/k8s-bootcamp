#!/usr/bin/env bash
# Track B 02: kubeadm init + worker join を一括で
# 前提: 01-terraform-vpc-ec2 が apply 済み、cloud-init が完了
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CH_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_DIR="$(cd "$CH_DIR/../01-terraform-vpc-ec2/terraform" && pwd)"
KEY="${SSH_KEY:-$HOME/.ssh/k8s-bootcamp}"

CP_PUBLIC=$(terraform -chdir="$TF_DIR" output -raw cp_public_ip)
CP_PRIVATE=$(terraform -chdir="$TF_DIR" output -raw cp_private_ip)
mapfile -t WORKERS < <(terraform -chdir="$TF_DIR" output -json worker_public_ips | jq -r '.[]')

echo "cp public=$CP_PUBLIC private=$CP_PRIVATE"
echo "workers=${WORKERS[*]}"

# kubeadm-config を生成して送り込む
sed "s/__CP_PRIVATE__/${CP_PRIVATE}/g" "$CH_DIR/manifests/kubeadm-config.yaml" > /tmp/kubeadm-config.yaml
scp -i "$KEY" -o StrictHostKeyChecking=no /tmp/kubeadm-config.yaml ubuntu@"$CP_PUBLIC":/tmp/
scp -i "$KEY" -o StrictHostKeyChecking=no "$CH_DIR/manifests/admission-config.yaml" ubuntu@"$CP_PUBLIC":/tmp/

ssh -i "$KEY" -o StrictHostKeyChecking=no ubuntu@"$CP_PUBLIC" bash <<'REMOTE'
set -euo pipefail
sudo mkdir -p /etc/kubernetes/admission
sudo cp /tmp/admission-config.yaml /etc/kubernetes/admission/admission-config.yaml
sudo kubeadm init \
  --config /tmp/kubeadm-config.yaml \
  --skip-phases=addon/kube-proxy \
  --upload-certs | tee /tmp/kubeadm-init.log
REMOTE

# kubeconfig を回収して server を public IP に書き換え
ssh -i "$KEY" -o StrictHostKeyChecking=no ubuntu@"$CP_PUBLIC" 'sudo cat /etc/kubernetes/admin.conf' > "$CH_DIR/kubeconfig"
sed -i.bak "s|server: https://${CP_PRIVATE}:6443|server: https://${CP_PUBLIC}:6443|" "$CH_DIR/kubeconfig"
echo "kubeconfig saved to $CH_DIR/kubeconfig"
export KUBECONFIG="$CH_DIR/kubeconfig"

# join command を取得
JOIN_CMD=$(ssh -i "$KEY" -o StrictHostKeyChecking=no ubuntu@"$CP_PUBLIC" 'sudo kubeadm token create --print-join-command')
echo "join: $JOIN_CMD"

for w in "${WORKERS[@]}"; do
  echo "==== join $w ===="
  ssh -i "$KEY" -o StrictHostKeyChecking=no ubuntu@"$w" "sudo $JOIN_CMD"
done

kubectl --kubeconfig "$CH_DIR/kubeconfig" get nodes -o wide
