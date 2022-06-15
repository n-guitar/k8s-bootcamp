# k8s bootcamp
- いろんなことを無視してdocker/k8sを動かして覚えるrepo
- 最後のchapterでk8s上で簡単なweb/ap/db構成のアプリケーションを作成します。
- IngressControllerを利用し、L7ロードバランス先の特定のFQDNにアクセスするため、`ワイルドカードDNS`または`hostファイル`を利用します。mac等で`ワイルドカードDNS`を利用したい場合は以下のrepoを参考にしてください。<br>

- dockerでdnsを起動し、mac上でワイルドカードdnsを作成する。<br>
https://github.com/n-guitar/alpine-dnsmasq<br>


## 動作確認済環境
```sh
# Macbook Pro Intel
$ sw_vers
ProductName:    macOS
ProductVersion: 11.6.4
BuildVersion:   20G417

# VM
$ vagrant --version
Vagrant 2.2.10

$ VBoxManage -v
6.1.34r150636
```

## virtualbox + vagrant + kubeadm による環境構築

||docs|概要|
|---|---|---|
|vagrant|[k8s_on_virtualbox2/doc.md](k8s_on_virtualbox2/doc.md)|Ubuntu 21.10でcontrol plane×1 worker×1 (2)|
|vagrant|[package_box/doc.md](package_box/doc.md)|Ubuntu 21.10でcontrol plane×1 worker×1 (2) <br>k8sを予めPackagingしたイメージを利用<br> vm起動後kubeadm init/joinを行う|


## chapter

|chapter|docs|概要|
|---|---|---|
|chapter1|[chapter1/ex.md](chapter1/ex.md)|簡単なdockerの操作|
|chapter2|[chapter2/ex.md](chapter2/ex.md)|kubectlの操作環境の確認とcore componentの確認|
|chapter3|[chapter3/ex.md](chapter3/ex.md)|Pod、ReplicaSet、Deploymentの操作|

## virtualbox
- https://www.oracle.com/jp/virtualization/technologies/vm/downloads/virtualbox-downloads.html

## vagrant
- https://www.vagrantup.com/downloads
## lima
- https://github.com/lima-vm/lima
