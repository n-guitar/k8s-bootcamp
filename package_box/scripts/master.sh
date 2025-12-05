#!/bin/bash
#
# Setup for Control Plane (Master) servers

set -euxo pipefail

local_ip="$(ip --json a s | jq -r '.[] | if .ifname == "eth1" then .addr_info[] | if .family == "inet" then .local else empty end else empty end')"

cat <<EOF | sudo tee /etc/default/kubelet
KUBELET_EXTRA_ARGS=--node-ip=$local_ip
EOF

# disable swap
sudo swapoff -a

sudo systemctl daemon-reload
sudo systemctl restart kubelet

MASTER_IP="192.168.200.10"
NODENAME=$(hostname -s)
POD_CIDR="10.244.0.0/16"

sudo kubeadm init --apiserver-advertise-address=$MASTER_IP --apiserver-cert-extra-sans=$MASTER_IP --pod-network-cidr=$POD_CIDR --node-name="$NODENAME" --ignore-preflight-errors=Swap

mkdir -p "$HOME"/.kube
sudo cp -i /etc/kubernetes/admin.conf "$HOME"/.kube/config
sudo chown "$(id -u)":"$(id -g)" "$HOME"/.kube/config

# Install Calico Network Plugin
kubectl apply -f /var/opt/calico.yaml

# Install Metrics Server

kubectl apply -f /var/opt/metrics-server.yaml

# Install Kubernetes Dashboard

kubectl apply -f /var/opt/recommended.yaml

# Create Dashboard User

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
EOF

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
EOF
