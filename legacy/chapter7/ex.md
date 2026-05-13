# NamespaceとDNS

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


## NamespaceとDNS

### Namespaceの作成

- 以下のNamespaceを作成し、applyする

```sh
# yamlの作成
# 以下のyaml定義をコピーしてyamlファイルを作成する
$ vi /tmp/my-namespace.yaml
$ k apply -f /tmp/my-namespace.yaml
```

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: develop
```

```sh
# 確認
# 削除せずとっておく
$ k get namespace
```

### Namespaced Resourcesの作成

- develop namespaceにdeploymentを作成する

- 以下のNamespaceを作成し、applyする

```sh
# yamlの作成
# 以下のyaml定義をコピーしてyamlファイルを作成する
$ vi /tmp/ns-deploy.yaml
$ k apply -f /tmp/ns-deploy.yaml
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: frontend
  name: frontend
  namespace: develop
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - image: nginx:alpine
        name: nginx
```

```sh
# 確認
# 削除せずとっておく
$ k get pod -n develop
```

### NamespaceとDNS名
- 以下のNamespace、Deployment, Serviceを作成し、applyする

```sh
# yamlの作成
# 以下のyaml定義をコピーしてyamlファイルを作成する
$ vi /tmp/dns-ns-test.yaml
$ k apply -f /tmp/dns-ns-test.yaml
```

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: staging

---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: frontend
  name: frontend
  namespace: staging
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - image: nginx:alpine
        name: nginx

---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: backend
  name: backend
  namespace: staging
spec:
  replicas: 2
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
      - image: nginx:alpine
        name: nginx

---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: backend
  name: backend
  namespace: staging
spec:
  ports:
  - name: 80-80
    port: 80
    protocol: TCP
    targetPort: 80
  selector:
    app: backend
  type: ClusterIP
```

```sh
# 確認
$ k get pod -n staging
$ k get deploy -n staging
$ k get svc -n staging

# EndpointsにPodのipがアサインされていること
$ k describe svc backend -n staging

# 同じNamespace同士の通信
# frontend → backend
# staging namespaceのfrontendにshell
# service名でアクセスできる
$ k exec -it $(k get pod -l app=frontend -n staging -o name) -n staging -- curl backend
# FQDNでのアクセス
$ k exec -it $(k get pod -l app=frontend -n staging -o name) -n staging -- curl backend.staging.svc.cluster.local

# 異なるNamespace同士の通信
# frontend(develop) → backend(staging)
# 事前確認
$ k get pod -l app=frontend -n develop
$ k get pod -l app=backend -n staging
# service名でアクセスできない
$ k exec -it $(k get pod -l app=frontend -n develop -o name) -n develop curl backend
# FQDNでのアクセスできる
$ k exec -it $(k get pod -l app=frontend -n develop -o name) -n develop -- curl backend.staging.svc.cluster.local


# 削除
$ k delete -f /tmp/dns-ns-test.yaml
$ k delete -f /tmp/ns-deploy.yaml
$ k delete -f /tmp/my-namespace.yaml
```

## 練習問題

### ex1
- red namespaceとblue namespaceを作成せよ

### ex2
- red namespaceに以下の条件でDeploymentを作成せよ

```sh
# Deployment
name: front-app
image: nginx:alpine

```

### ex3
- blue namespaceに以下の条件でDeploymentとServiceを作成せよ

```sh
# Deployment
name: back-app
image: nginx:alpine

# Service
name: back-api-svc
image: nginx:alpine
type: clusterip
```

### ex4
- red namespaceのfront-appからcurlでblue namespaceのback-appにアクセスせよ
