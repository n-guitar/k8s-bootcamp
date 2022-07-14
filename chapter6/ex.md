# データの永続化 PV/PVC/StorageClassの操作

## (前提事項) Kubectlコマンドの補完 & エイリアス
```sh
$ source <(kubectl completion bash)
$ echo "source <(kubectl completion bash)" >> ~/.bashrc
$ alias k=kubectl
$ complete -F __start_kubectl k
```

## (前提事項)kubernetes clusterの情報確認
worker nodeが1台以上あること

```sh
# control-plane, workerが各1台以上Readyで存在していること
$ k get nodes
NAME            STATUS   ROLES                  AGE   VERSION
master-node     Ready    control-plane,master   99m   v1.22.10
worker-node01   Ready    worker                 88m   v1.22.10
worker-node02   Ready    worker                 78m   v1.22.10
```

Docker + k3s環境でもChapterを実施できます。

||docs|概要|
|---|---|---|
|Docker + k3s|[k3s_in_doccker/doc.md](../k3s_in_doccker/doc.md)|k3sでcontrol plane×1 worker×2<br>|

<br><br>

## 前準備(NFS Serverの構築)

### vagrant
mastar serverをnfs server代わりに利用する

- mastar

```sh
# nfs-server install && export
$ curl -sL https://raw.githubusercontent.com/n-guitar/k8s-bootcamp/main/chapter6/object/vagrant_nfs.sh | bash

# 確認
$ ls -l /nfsshare/
total 8
drwxr-xr-x 2 root root 4096 Jul 13 12:19 pv
drwxr-xr-x 2 root root 4096 Jul 13 12:19 storageclass

$ cat /etc/exports
・・・
/nfsshare *(rw,fsid=0,async,no_subtree_check,no_auth_nlm,insecure,no_root_squash)

# index.html作成 ※後でPodから利用
$ echo 'hello strage' > /nfsshare/pv/index.html
```

- 各node

```sh
$ sudo apt-get install -y nfs-common
```


### k3s

nfs server containerを起動する

```sh
$ docker run -d --name nfs --privileged -v /tmp:/nfsshare -e SHARED_DIRECTORY=/nfsshare --network=k3s_in_doccker_default itsthenetwork/nfs-server-alpine:12

# ディレクトリ作成
$ docker exec -it nfs /bin/sh -c "mkdir /nfsshare/pv"
$ docker exec -it nfs /bin/sh -c "mkdir /nfsshare/storageclass"

# 確認
$ docker ps -f "name=nfs"
CONTAINER ID   IMAGE                                COMMAND              CREATED         STATUS         PORTS     NAMES
f3f6e5bba76a   itsthenetwork/nfs-server-alpine:12   "/usr/bin/nfsd.sh"   8 minutes ago   Up 8 minutes             nfs

$ docker exec -it nfs ls -l /nfsshare
total 8
drwxr-xr-x    2 root     root            64 Jul 13 12:27 pv
drwxr-xr-x    2 root     root            64 Jul 13 12:27 storageclass

$ docker exec -it nfs cat /etc/exports
/nfsshare *(rw,fsid=0,async,no_subtree_check,no_auth_nlm,insecure,no_root_squash)

$ docker exec -it nfs /bin/sh -c "echo 'hello strage' > /nfsshare/pv/index.html"

# IPの確認 後ほど利用するので覚えておく
$ docker exec -it nfs hostname -i
```


## Containerの揮発性

### DeploymentとServiceの作成

- 以下のDeploymentとServiceを作成し、applyする

```sh
# yamlの作成
# 以下のyaml定義をコピーしてyamlファイルを作成する
$ vi /tmp/cc-web.yaml
$ k apply -f /tmp/cc-web.yaml
```

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: cc-web
  name: cc-web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cc-web
  template:
    metadata:
      labels:
        app: cc-web
    spec:
      containers:
      - image: nginx:alpine
        name: nginx

---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: cc-web-svc
  name: cc-web-svc
spec:
  ports:
  - name: 80-80
    port: 80
    protocol: TCP
    targetPort: 80
  selector:
    app: cc-web
  type: NodePort
status:
  loadBalancer: {}
```

```sh
# 確認
# nodeportを覚えておく
$ k get all -l 'app in (cc-web,cc-web-svc)'

# 確認
# Welcome to nginx! というページが返ってくる。
$ curl localhost:<nodeport>
・・・
<h1>Welcome to nginx!</h1>
・・・

# 直接コンテナ上でindex.htmlを書き換えてみる
$ k get pod -l app=cc-web
# pod(container)内にログイン
$ k exec -it $(k get pod -l app=cc-web -o name) -- sh -c "echo 'hello k8s' > /usr/share/nginx/html/index.html"

# 確認
# hello k8s というページが返ってくる。
$ curl localhost:<nodeport>

# Podを削除する
$ k delete pod -l app=cc-web

# 確認
# Welcome to nginx! というページに戻ってしまう
$ curl localhost:<nodeport>

# 削除
k delete -f /tmp/cc-web.yaml
```



## NFSによる永続化

### PVの作成 (NFS)

- 以下のPersistentVolumeを作成し、applyする

```sh
# yamlの作成
# 以下のyaml定義をコピーしてyamlファイルを作成する
$ vi /tmp/pv.yaml
$ k apply -f /tmp/pv.yaml
```
- serverのIPを書き換える

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-pv
spec:
  capacity:
    storage: 5Mi
  accessModes:
    - ReadWriteMany
  nfs:
    server: <node ip or container ip>
    path: "/pv"
  mountOptions:
    - nfsvers=4.2
```

```sh
# Availableとなっていること
$ k get pv
NAME     CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM   STORAGECLASS   REASON   AGE
nfs-pv   5Mi        RWX            Retain           Available                                   5s

# 詳細
$ k describe pv nfs-pv
```
<br>

### PVCの作成


- 以下のPersistentVolumeClaimを作成し、applyする

```sh
# yamlの作成
# 以下のyaml定義をコピーしてyamlファイルを作成する
$ vi /tmp/pvc.yaml
$ k apply -f /tmp/pvc.yaml
```

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-pvc
spec:
  accessModes:
  - ReadWriteMany
  storageClassName: ""
  resources:
    requests:
      storage: 5Mi
  volumeName: nfs-pv
  volumeMode: Filesystem
```

```sh
# PVの確認 STATUSがAvailable→Bound、CLAIM状態になっている
$ k get pv
NAME     CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM             STORAGECLASS   REASON   AGE
nfs-pv   5Mi        RWX            Retain           Bound    default/nfs-pvc                           2m40s

# PVCの確認
# 作成した瞬間はSTATUSがPending状態のこともあるため、少し待つ
$ k get pvc
NAME      STATUS   VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
nfs-pvc   Bound    nfs-pv   5Mi        RWX                           85s

# 詳細確認
$ k describe pvc nfs-pvc
```
<br>

### DeploymentとServiceの作成

- 以下のDeploymentとServiceを作成し、applyする

```sh
# yamlの作成
# 以下のyaml定義をコピーしてyamlファイルを作成する
$ vi /tmp/nfs-web.yaml
$ k apply -f /tmp/nfs-web.yaml
```

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: nfs-web
  name: nfs-web
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nfs-web
  template:
    metadata:
      labels:
        app: nfs-web
    spec:
      containers:
      - image: nginx:1.21-alpine
        name: nginx
        volumeMounts:
        - name: nfs-volume
          mountPath: /usr/share/nginx/html
      volumes:
      - name: nfs-volume
        persistentVolumeClaim:
          claimName: nfs-pvc
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: nfs-web-svc
  name: nfs-web-svc
spec:
  ports:
  - name: 80-80
    port: 80
    protocol: TCP
    targetPort: 80
  selector:
    app: nfs-web
  type: NodePort
status:
  loadBalancer: {}
```

```sh
# 確認
# nodeportを覚えておく
$ k get all -l 'app in (nfs-web,nfs-web-svc)'

# 確認
$ curl localhost:<nodeport>
hello strage

# podを削除してもコンテンツが消えないことを確認
$ k delete pod -l app=nfs-web && k get po

# 削除
$ k delete -f /tmp/nfs-web.yaml
$ k delete -f /tmp/pvc.yaml
$ k delete -f /tmp/pv.yaml
```
<br>


## StorageClass (Coming Soon!!)


## 練習問題

### ex1
- local volumeを利用して以下の条件でwebサーバのコンテツを永続化せよ
- nginxのindex.htmlにはhello hostpathと表示されるようにせよ
- ドキュメント
  - https://kubernetes.io/docs/concepts/storage/volumes/#local

- 条件
<br>※その他のオプションは任意とする

```sh
# Deployment
replicas: 1
name: ex1-pod
image: nginx:alpine
nodeName: worker-node01 or k3s-worker1

# Service
type: NodePort
name: ex1-svc

# PersistentVolume
# 必要に応じてローカルディレクトリの作成を行うこと
name: hostpath-pv
local.path: /data
capacity.storage: 5Mi
accessModes.ReadWriteMany

# PersistentVolumeClaim
name: hostpath-pvc
resources.requests.storage: 5Mi
```
