# 環境構築

## 動作確認済環境
```sh
# docker
$ docker version
Client: Docker Engine - Community
 Version:           20.10.5
 OS/Arch:           darwin/amd64

Server: Docker Engine - Community
 Engine:
  Version:          20.10.5

# docker-compose
docker-compose version 1.29.0

# mac
$ sw_vers
ProductName:    macOS
ProductVersion: 11.6.4
BuildVersion:   20G417
```
- ※M1 macbook air でも動作を確認


## k3s構築
```sh
# k8s_on_virtualbox配下に移動
$ cd k3s_in_doccker
$ pwd
XXXX/k8s-bootcamp/k3s_in_doccker

# docker実行
K3S_TOKEN=${RANDOM}${RANDOM}${RANDOM} K3S_VERSION=v1.22.10-k3s1 docker-compose up -d

# docker container
K3S_TOKEN=${RANDOM}${RANDOM}${RANDOM} docker-compose ps

# kubernetesへの接続
export KUBECONFIG=./kubeconfig.yaml

# node
kubectl get nodes
```

## 環境の削除

```sh
# コンテナの停止
K3S_TOKEN=${RANDOM}${RANDOM}${RANDOM} docker-compose down

# ボリュームの削除
docker volume rm sre-study-kubernetes_k3s-server
docker volume rm sre-study-kubernetes_k3s-worker-data

# イメージの削除
docker images | grep "rancher/k3s" | awk '{print $3}' | xargs -I '{}' docker rmi '{}'

```
