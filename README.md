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
|vagrant|[k8s_on_virtualbox/doc.md](k8s_on_virtualbox/doc.md)|Ubuntu 20.04.4 LTSでcontrol plane×1 worker×1|


## chapter

|chapter|docs|概要|
|---|---|---|
|chapter1|[chapter1/ex.md](chapter1/ex.md)|簡単なdockerの操作|

## virtualbox
- https://www.oracle.com/jp/virtualization/technologies/vm/downloads/virtualbox-downloads.html

## vagrant
- https://www.vagrantup.com/downloads
## lima
- https://github.com/lima-vm/lima
