#!/bin/sh
echo "worker init start"

echo "swap off"
free -m
sudo swapoff -a
cat /etc/fstab
sudo sed -ri '/ swap /s/^(.*)$/#\1/g' /etc/fstab
free -m

echo "カーネルパラメータの設定"
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
cat /etc/sysctl.d/99-kubernetes-cri.conf

cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF
cat /etc/modules-load.d/containerd.conf

sudo modprobe overlay
sudo modprobe br_netfilter

sudo sysctl --system

echo "firewalld停止"
sudo systemctl stop firewalld
sudo systemctl disable firewalld

echo "iptablesをLegacyモードへ切替"
sudo apt-get install -y iptables arptables ebtables
sudo update-alternatives --set iptables /usr/sbin/iptables-legacy
sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
sudo update-alternatives --set arptables /usr/sbin/arptables-legacy
sudo update-alternatives --set ebtables /usr/sbin/ebtables-legacy


echo "kubelet kubeadm kubectl install"
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
sudo apt-get update
sudo apt-get install -y kubelet=1.22.10-00 kubeadm=1.22.10-00 kubectl=1.22.10-00
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet

echo "containerdのinstall"
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository \
    "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) \
    stable"
sudo apt-get update
sudo apt-get install -y containerd.io=1.5.11-1
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /tmp/config.toml
sudo sed -e "s/SystemdCgroup = false/SystemdCgroup = true/" /tmp/config.toml | sudo tee /etc/containerd/config.toml
sudo systemctl restart containerd

echo "end"
