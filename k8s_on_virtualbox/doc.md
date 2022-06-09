# 環境構築

## VM作成

- Mac

```sh
# k8s_on_virtualbox配下に移動
$ cd k8s_on_virtualbox
$ pwd
/XXXXXXX/k8s-bootcamp/k8s_on_virtualbox
$ vagrant up

# ブリッジNWを聞かれたら答える
worker01: Which interface should the network bridge to?

$ vagrant status
Current machine states:

controlplane01            running (virtualbox)
worker01                  running (virtualbox)
```

## Control Plane OSの設定
VM内で実施

```sh
# swap off確認
# このVMではもともとOFF
$ free -m
$ sudo swapoff -a
$ cat /etc/fstab
$ sudo sed -ri '/ swap /s/^(.*)$/#\1/g' /etc/fstab
$ free -m

# カーネルパラメータの設定
$ cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv6.conf.all.disable_ipv6      = 1
net.ipv6.conf.default.disable_ipv6  = 1
net.ipv6.conf.lo.disable_ipv6       = 1
EOF
$ cat /etc/sysctl.d/99-kubernetes-cri.conf

$ cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF
$ cat /etc/modules-load.d/containerd.conf

$ sudo modprobe overlay
$ sudo modprobe br_netfilter

$ sudo sysctl --system

cat <<'EOF' | sudo tee -a /etc/rc.local
#!/bin/bash
# /etc/rc.local

# Load kernel variables from /etc/sysctl.d
/etc/init.d/procps restart

exit 0
EOF

#実行権限を付与
sudo chmod 755 /etc/rc.local

# firewalld停止
# このVMではもともと動作していない
$ systemctl status firewalld
$ sudo systemctl stop firewalld
$ sudo systemctl disable firewalld
$ systemctl status firewalld

# iptablesをLegacyモードへ切替
$ sudo apt-get install -y iptables arptables ebtables

# レガシーバージョンに切り替え
$ sudo update-alternatives --set iptables /usr/sbin/iptables-legacy
$ sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
$ sudo update-alternatives --set arptables /usr/sbin/arptables-legacy
$ sudo update-alternatives --set ebtables /usr/sbin/ebtables-legacy
```

## kubelet kubeadm kubectl install
- ドキュメント

https://kubernetes.io/ja/docs/setup/production-environment/tools/kubeadm/install-kubeadm/

```sh
# HTTPS越しのリポジトリの使用をaptに許可するために、パッケージをインストール
$ sudo apt-get update
$ sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common

# kubelet kubeadm kubectl install
$ curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
$ cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
$ sudo apt-get update
$ apt-cache madison kubelet kubeadm kubectl|grep 1.22

# 今回は1.22.10-00とする
$ sudo apt-get install -y kubelet=1.22.10-00 kubeadm=1.22.10-00 kubectl=1.22.10-00
$ sudo apt-mark hold kubelet kubeadm kubectl

# kubeadmが何をすべきか指示するまで、kubeletはクラッシュループで数秒ごとに再起動する
$ sudo systemctl enable --now kubelet

```


## containerdのinstall
- k8sとcontainerdの推奨バージョン

https://containerd.io/releases/

今回はk8s 1.22→1.23,1.24を想定し、どのバージョンでも推奨の1.5.11+をinstallする

- containerd install ドキュメント

https://kubernetes.io/ja/docs/setup/production-environment/container-runtimes/#containerd


```sh
## リポジトリの設定

## Docker公式のGPG鍵を追加
$ curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

## Dockerのaptリポジトリの追加
$ sudo add-apt-repository \
    "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) \
    stable"

## containerdのインストール
$ sudo apt-get update
$ apt-cache madison containerd.io
containerd.io |    1.6.6-1 | https://download.docker.com/linux/ubuntu jammy/stable amd64 Packages
containerd.io |    1.6.4-1 | https://download.docker.com/linux/ubuntu jammy/stable amd64 Packages
containerd.io |   1.5.11-1 | https://download.docker.com/linux/ubuntu jammy/stable amd64 Packages
containerd.io |   1.5.10-1 | https://download.docker.com/linux/ubuntu jammy/stable amd64 Packages

$ sudo apt-get install -y containerd.io=1.5.11-1

# containerdの設定
$ sudo mkdir -p /etc/containerd
$ containerd config default | sudo tee /tmp/config.toml
# Configuring a cgroup driver
$ grep SystemdCgroup /tmp/config.toml
$ sudo sed -e "s/SystemdCgroup = false/SystemdCgroup = true/" /tmp/config.toml | sudo tee /etc/containerd/config.toml
$ diff /tmp/config.toml /etc/containerd/config.toml

# containerdの再起動
$ sudo systemctl restart containerd
$ sudo systemctl status containerd
```


## k8s Clusterの作成
- networkは今回canalを利用

https://projectcalico.docs.tigera.io/getting-started/kubernetes/flannel/flannel

```sh
# api serverが想定のバージョンになっていることを確認
$ sudo kubeadm config images list
# image pull
$ sudo kubeadm config images pull --cri-socket=unix:///run/containerd/containerd.sock

# Initializing your control-plane node
$ ls -l /vagrant/kubeadm-config.yaml
$ sudo kubeadm init --config /vagrant/kubeadm-config.yaml

$ mkdir -p $HOME/.kube
$ sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
$ sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Installing a Pod network add-on
$ kubectl apply -f https://projectcalico.docs.tigera.io/manifests/canal.yaml

# 全てのpodがRunningになるまで待機 ※Ctr + Cで終了
$ watch -n 1 kubectl get po -n kube-system

# 確認
$ kubectl get nodes
NAME             STATUS   ROLES                  AGE     VERSION
controlplane01   Ready    control-plane,master   3m40s   v1.22.10
```

## worker join用のトークン確認
```sh
# それぞれのトークンを覚えておく
$ sudo kubeadm token list
$ openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | \
   openssl dgst -sha256 -hex | sed 's/^.* //'
```



## Worker OS設定,k8s module install
```sh
$ cd /vagrant/
$ ls -l init.sh
-rwxr-xr-x 1 vagrant vagrant 2144 Jun  9 03:26 init.sh
$ sh init.sh
```

## workerをクラスターに参加させる
- workerで実施

```sh
$ sudo kubeadm join 192.168.200.11:6443 --token <controlPlaneのkubeadm token listの値> \
        --discovery-token-ca-cert-hash sha256:<controlPlaneのopenssl xxx の値>
```

## 確認
```sh
$ kubectl get nodes
NAME             STATUS   ROLES                  AGE     VERSION
controlplane01   Ready    control-plane,master   3m31s   v1.22.10
worker01         Ready    <none>                 2m8s    v1.22.10
```
