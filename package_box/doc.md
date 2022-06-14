# 環境構築


# master(control-plane)
## master VM作成

- Mac/Win

```sh
# package_box配下に移動
$ cd package_box
$ pwd
/XXXXXXX/k8s-bootcamp/package_box
$ vagrant up master
$ vagrant ssh master
```

## k8s control plane作成
```sh
$ curl -sL https://raw.githubusercontent.com/n-guitar/k8s-bootcamp/main/package_box/scripts/master.sh | bash

# 確認
$ kubectl get nodes
# 結果
NAME          STATUS   ROLES                  AGE   VERSION
master-node   Ready    control-plane,master   36s   v1.22.10
```

- join コマンド作成
```sh
$ sudo kubeadm token create --print-join-command
# 結果をコピーしておく(node側で利用)
kubeadm join 192.168.200.10:6443 --token XXXXXXXX --discovery-token-ca-cert-hash sha256:XXXXXXXX
```

# node

## node VM作成

- Mac/Win

```sh
# package_box配下に移動
$ cd package_box
$ pwd
/XXXXXXX/k8s-bootcamp/package_box
$ vagrant up node01
$ vagrant ssh node01
```

## k8s node作成
```sh
$ curl -sL https://raw.githubusercontent.com/n-guitar/k8s-bootcamp/main/package_box/scripts/node.sh | bash
```

## k8s cluster join
```sh
$ sudo kubeadm join 192.168.200.10:6443 --token XXXXXXXX --discovery-token-ca-cert-hash sha256:XXXXXXXX
```


## masterから確認&role設定
```sh
$ kubectl get nodes
# 結果
NAME            STATUS   ROLES                  AGE   VERSION
master-node     Ready    control-plane,master   26m   v1.22.10
worker-node01   Ready    <none>                 32s   v1.22.10

$ kubectl label node worker-node01 node-role.kubernetes.io/worker=worker
$ kubectl get nodes
# 結果
NAME            STATUS   ROLES                  AGE   VERSION
master-node     Ready    control-plane,master   27m   v1.22.10
worker-node01   Ready    worker                 57s   v1.22.10
```
