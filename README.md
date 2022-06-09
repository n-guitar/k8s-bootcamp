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



## chapter

|chapter|概要||
|---|---|---|
|chapter1|[chapter1/ex.md](chapter1/ex.md)|簡単なdockerの操作|

## lima
- 以下公式gitにsampleでk8s,k3sが用意されているがubuntuイメージから設定していく。
- https://github.com/lima-vm/lima
