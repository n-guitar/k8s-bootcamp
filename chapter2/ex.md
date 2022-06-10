# kubectlの操作と環境確認

## チュートシート
- https://kubernetes.io/ja/docs/reference/kubectl/cheatsheet/


## Kubectlコマンドの補完 & エイリアス
```sh
$ source <(kubectl completion bash)
$ echo "source <(kubectl completion bash)" >> ~/.bashrc
$ alias k=kubectl
$ complete -F __start_kubectl k
```

## kubernetes clusterの情報確認
```sh
# nodeの情報とステータス確認
$ k get nodes

# 詳細を表示
$ k get nodes -o wide

# nodeごとの詳細を表示
$ k describe node <node名>

# nodeのlabelを表示
$ k get nodes --show-labels
```

## core componentの確認
```sh
# core
$ k -n kube-system get pod

# どのnodeで稼働しているか
$ k -n kube-system get pod -o wide

# 個別pod
# k -n kube-system get pod <pod名>
$ k -n kube-system get pod etcd-master-node

# 個別podのyaml表示
# k -n kube-system get pod <pod名> -o yaml
# etcd, kube-apiserver, kube-schedulerをそれぞれ確認する
# それぞれどんなcontainerが動作していて、どんなコマンドを実行しているだろうか？それどのportで動作している？
$ k -n kube-system get pod etcd-master-node -o yaml

# kubeletは通常nodeのdaemonで動作
# 設定ファイルを見てみよう。何が書かれているか？api serverとの通信の設定はどこか？
# ex3 etcd, kube-apiserver, kube-schedulerはstatic podと呼ばれている
$ sudo systemctl status kubelet

# kube-proxy
# どのnodeで動作しているか？
# daemonsetとは？
$ k -n kube-system get pod --selector=k8s-app=kube-proxy
$ k -n kube-system get ds

# coredns, calico, (etrics-server)は別のセクションで実施します。
```


### 練習問題

#### ex1
- 各nodeの詳細を調べ、Taintsの値を調べよ。
- またTaintsとはどのようなときに使われるか調査し説明せよ。

#### ex2
- nodeのlabelを利用してk get nodesで表示されるnodeをmaster-nodeのみにフィルターせよ。

#### ex3
- etcd, kube-apiserver, kube-schedulerはstatic podと呼ばれている。特定のnodeのkubeletに紐付けられているが、どこにpodの定義があるかPathを答えよ。

#### ex4
- api server podの定義を確認し利用されているtls-cert-file,tls-private-keyのpathを答えよ
- curl を利用してapi serverのバージョンを取得せよ

```sh
$ curl https://<api server>:port/version --cacert <tls-cert-file> --key <tls-private-key>
```

#### ex5
- etcdの定義を確認し、cert-file、key-file、trusted-ca-fileのpathを答えよ
- kubectl execコマンドを利用して etcdctl member listを取得せよ

```sh
k -n kube-system exec etcd-master-node  -- sh -c "ETCDCTL_API=3 etcdctl member list --cacert <trusted-ca-file> --cert <cert-file> --key <key-file>"
```

#### ex6
- kubeadm certs check-expirationで各証明書の期限を表示せよ
