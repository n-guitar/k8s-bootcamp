# 環境構築


## Control Plane用VM作成

```sh
# k8s-bootcampディレクトリ
$ pwd
XXXXXX/k8s-bootcamp

# config yaml編集
$ LIMA_VM_WORK_VOLUME=`echo ${PWD}/k8s_on_lima/work_volume | sed 's/\//\\\\\//g'`
$ echo $LIMA_VM_WORK_VOLUME
$ sed -e "s/work_volume/${LIMA_VM_WORK_VOLUME}/" ./k8s_on_lima/ubuntu.yaml > ./k8s_on_lima/k8s_controlplane.yaml
$ diff ./k8s_on_lima/ubuntu.yaml ./k8s_on_lima/k8s_controlplane.yaml

# vm 作成&起動
$ limactl start --name=controlplane01 ./k8s_on_lima/k8s_controlplane.yaml
? Creating an instance "ubuntu"  [Use arrows to move, type to filter]
> Proceed with the current configuration
  Open an editor to review or modify the current configuration
  Choose another example (docker, podman, archlinux, fedora, ...)
  Exit

# 確認
$ limactl list
NAME              STATUS     SSH                ARCH      CPUS    MEMORY    DISK     DIR
controlplane01    Running    127.0.0.1:52289    x86_64    2       4GiB      20GiB    /XXXXXX/.lima/controlplane01

$ limactl shell controlplane01
$ uname -a
Linux lima-controlplane01 5.15.0-25-generic #25-Ubuntu SMP Wed Mar 30 15:54:22 UTC 2022 x86_64 x86_64 x86_64 GNU/Linux
```

## OSの設定
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

## k8s Cluster用config確認
- リファレンス

https://kubernetes.io/ja/docs/setup/production-environment/tools/kubeadm/control-plane-flags/

- kubeadm-config.yaml

[kubeadm-config.yaml](volume/kubeadm-config.yaml)
```yaml
kind: InitConfiguration
apiVersion: kubeadm.k8s.io/v1beta3
nodeRegistration:
  criSocket: unix:///run/containerd/containerd.sock
---
kind: ClusterConfiguration
apiVersion: kubeadm.k8s.io/v1beta3
apiServer:
  certSANs: # --apiserver-cert-extra-sans
  - "127.0.0.1"
networking:
  podSubnet: "10.244.0.0/16" # --pod-network-cidr
---
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
cgroupDriver: systemd
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
# lima vmのmountポイントにあるファイルを確認
$ ls -l ./k8s_on_lima/work_volume/kubeadm-config.yaml
$ sudo kubeadm init --config ./k8s_on_lima/work_volume/kubeadm-config.yaml

$ mkdir -p $HOME/.kube
$ sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
$ sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Installing a Pod network add-on
$ kubectl apply -f https://projectcalico.docs.tigera.io/manifests/canal.yaml

# 全てのpodがRunningになるまで待機 ※Ctr + Cで終了
$ watch -n 1 kubectl get po -n kube-system

# 確認
$ kubectl get nodes
NAME                  STATUS   ROLES                  AGE   VERSION
lima-controlplane01   Ready    control-plane,master   13m   v1.22.10
```

## worker join用のトークン確認
```sh
# それぞれのトークンを覚えておく
$ sudo kubeadm token list
$ openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | \
   openssl dgst -sha256 -hex | sed 's/^.* //'
```


## Worker用VM作成
```sh
# k8s-bootcampディレクトリ
$ pwd
XXXXXX/k8s-bootcamp

# config yaml編集
$ LIMA_VM_WORK_VOLUME=`echo ${PWD}/k8s_on_lima/work_volume | sed 's/\//\\\\\//g'`
$ echo $LIMA_VM_WORK_VOLUME
$ sed -e "s/work_volume/${LIMA_VM_WORK_VOLUME}/" ./k8s_on_lima/ubuntu.yaml > ./k8s_on_lima/k8s_worker.yaml
$ diff ./k8s_on_lima/ubuntu.yaml ./k8s_on_lima/k8s_worker.yaml

# vm 作成&起動
$ limactl start --name=worker01 ./k8s_on_lima/k8s_worker.yaml
? Creating an instance "ubuntu"  [Use arrows to move, type to filter]
> Proceed with the current configuration
  Open an editor to review or modify the current configuration
  Choose another example (docker, podman, archlinux, fedora, ...)
  Exit

# 確認
$ limactl list
NAME              STATUS     SSH                ARCH      CPUS    MEMORY    DISK     DIR
controlplane01    Running    127.0.0.1:59837    x86_64    2       4GiB      20GiB    /XXXXX/.lima/controlplane01
worker01          Running    127.0.0.1:62789    x86_64    2       4GiB      20GiB    /XXXXX/.lima/worker01

$ limactl shell worker01
$ uname -a
Linux lima-worker01 5.15.0-25-generic #25-Ubuntu SMP Wed Mar 30 15:54:22 UTC 2022 x86_64 x86_64 x86_64 GNU/Linux
```

## worker init (課題あり)
limaの場合ipが固定で 192.168.5.15/24に割当ってしまう。

```sh
# ip 変更
# limaはデフォルトで192.168.5.15を全てに割り当ててしまうためIPがかぶる
$ sudo vi /etc/netplan/99-netcfg.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: false
      dhcp6: false
      addresses:
        - 192.168.5.16/24
      gateway4: 192.168.5.2
      nameservers:
        addresses:
          - 192.168.5.3
$ sudo mv /etc/netplan/50-cloud-init.yaml /etc/netplan/50-cloud-init.yaml.bk
$ sudo netplan apply

# os設定 & k8s module install
$ cd ./k8s_on_lima/work_volume/
$ sudo chmod 755 ./worker_init.sh
$ sh ./worker_init.sh
```

## workerをクラスターに参加させる(未)

```sh
$ sudo kubeadm join <ccontrolPlaneのip>:6443 --token <controlPlaneのkubeadm token listの値> \
        --discovery-token-ca-cert-hash sha256:<controlPlaneのopenssl xxx の値>
```
