# 環境構築


## 前準備
- k8s_on_virtualboxにバグが有り,,,,,,,,/etc/vbox/networks.confファイルを作成/編集して以下を追加する必要がある

```sh
$ sudo mkdir -p /etc/vbox/
$ echo "* 0.0.0.0/0 ::/0" | sudo tee -a /etc/vbox/networks.conf
```

## master VM作成

- Mac

```sh
# k8s_on_virtualbox配下に移動
$ cd k8s_on_virtualbox2
$ pwd
/XXXXXXX/k8s-bootcamp/k8s_on_virtualbox2
$ vagrant up master

# 確認
$ vagrant ssh master
$ kubectl get nodes
```

## worker VM作成
```sh
# k8s_on_virtualbox配下に移動
$ cd k8s_on_virtualbox2
$ pwd
/XXXXXXX/k8s-bootcamp/k8s_on_virtualbox2
$ vagrant up node01

# 確認
# Readyになっているか
$ vagrant ssh master
$ kubectl get nodes
```


## (Option) Mac上からの操作
- ※kubectl client必要
```sh
# k8s_on_virtualbox配下に移動
$ cd k8s_on_virtualbox2/configs
$ pwd
/XXXXXXX/k8s-bootcamp/k8s_on_virtualbox2/configs
$ export KUBECONFIG=$(pwd)/config
$ kubectl get nodes
```
