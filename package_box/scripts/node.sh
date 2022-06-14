#!/bin/bash
#
# Setup for Node servers
set -euxo pipefail

local_ip="$(ip --json a s | jq -r '.[] | if .ifname == "eth1" then .addr_info[] | if .family == "inet" then .local else empty end else empty end')"

cat <<EOF | sudo tee /etc/default/kubelet
KUBELET_EXTRA_ARGS=--node-ip=$local_ip
EOF

# disable swap
sudo swapoff -a

sudo systemctl daemon-reload
sudo systemctl restart kubelet
