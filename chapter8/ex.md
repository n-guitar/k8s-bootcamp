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

## 注意
Docker + k3s環境でもChapterを実施できますが既存のIngressControllerを利用しないため、起動ファイルを以下のように変更してください。<br>
既存でDocker + k3s環境が動作している場合は一度すべて削除してください。

### 削除コマンド
以下手順を参考

||docs|概要|
|---|---|---|
|Docker + k3s|[k3s_in_doccker/doc.md](../k3s_in_doccker/doc.md)|k3sでcontrol plane×1 worker×2<br>|

### 起動コマンド

```sh
$ K3S_TOKEN=${RANDOM}${RANDOM}${RANDOM} K3S_VERSION=v1.22.10-k3s1 docker-compose -f ./docker-compose_desable-traefik.yaml up -d
```


<br><br>


## IngressControllerの構築

- 以下のコマンドを実行
```sh
# 内容は本Chapterでは割愛
# nginx Ingress Controller
$ k apply -f https://raw.githubusercontent.com/nginxinc/kubernetes-ingress/release-2.3/deployments/common/ns-and-sa.yaml
$ k apply -f https://raw.githubusercontent.com/nginxinc/kubernetes-ingress/release-2.3/deployments/rbac/rbac.yaml
$ k apply -f https://raw.githubusercontent.com/nginxinc/kubernetes-ingress/release-2.3/deployments/common/default-server-secret.yaml
$ k apply -f https://raw.githubusercontent.com/nginxinc/kubernetes-ingress/release-2.3/deployments/common/nginx-config.yaml
$ k apply -f https://raw.githubusercontent.com/nginxinc/kubernetes-ingress/release-2.3/deployments/common/ingress-class.yaml

$ k apply -f https://raw.githubusercontent.com/n-guitar/k8s-bootcamp/main/nginx_ingress/nginx-ingress.yaml
```

- 確認
```sh
# 確認
$ k get deploy -n kube-system -l k8s-app=traefik-ingress-lb
NAME                         READY   UP-TO-DATE   AVAILABLE   AGE
traefik-ingress-controller   1/1     1            1           2m11s

$ k get svc -n kube-system traefik-ingress-service
NAME                      TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)                       AGE
traefik-ingress-service   NodePort   10.99.121.120   <none>        80:32707/TCP,8080:30597/TCP   10m
```

## Ingressの作成

### nginxをDeployment、ClusterIPで作成する

```sh
# Deployment
# コマンドで作成してみる
# dry run
$ k create deployment cap8-web --image=nginx:alpine --replicas=2 --dry-run=client -o yaml
# 内容が問題なければ実行
$ k create deployment cap8-web --image=nginx:alpine --replicas=2
# 確認
$ k get pod -l app=cap8-web
$ k get deploy -l app=cap8-web

# Service
# dry run
$ k create service clusterip cap8-web --tcp=80:80 --dry-run=client -o yaml
# 内容が問題なければ実行
$ k create service clusterip cap8-web --tcp=80:80
$ k get svc -l app=cap8-web
# EndpointsにIPが入っていればOK
$ k describe svc -l app=cap8-web
```

### Ingressの作成
- 以下のIngressを作成し、applyする

```sh
# yamlの作成
# 以下のyaml定義をコピーしてyamlファイルを作成する
$ vi /tmp/cap8-ingress.yaml
$ k apply -f /tmp/cap8-ingress.yaml
```

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: cap8-web
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
  - host: cap8-web.local
    http:
      paths:
      - backend:
          service:
            name: cap8-web
            port:
              number: 80
        path: /
        pathType: Prefix
```

```sh
# 確認
$ k get ing cap8-web
$ k describe ing cap8-web
```

### 接続確認

#### k3sの場合

```sh
# worker nodeのport 80 ※コンテナで80:10080, 80:20080をマッピングしている
$ curl -H 'Host:cap8-web.local' http://127.0.0.1:10080/
$ curl -H 'Host:cap8-web.local' http://127.0.0.1:20080/
```

#### vagrant環境の場合

```sh
# worker nodeのport 80
$ curl -H 'Host:cap8-web.local' http://192.168.200.11/
```

#### Laptopのhosts書き換える場合
- Mac
```sh
$ sudo vi /etc/hosts
# k3sの場合
127.0.0.1 cap8-web.local
# vagrant環境の場合
192.168.200.11 cap8-web.local
```

## 練習問題 (wordpressを作成)

### ex1
- 以下のコマンドでDB Server用のPasswordを管理するsecretsを作成せよ

※YOUR_PASSWORDは自分自身で設定すること(大文字、小文字、数字、記号を含む8文字以上)

```sh
# 確認
$ k create secret generic mysql-pass --from-literal=password="YOUR_PASSWORD" --dry-run=client -o yaml
# 実行
$ k create secret generic mysql-pass --from-literal=password="YOUR_PASSWORD"
```

### ex2
- ex1で作成した、secretsをdescribeコマンドで確認せよ。またpasswordに設定されている文字列をbase64でdecodeでよ

```sh
# decodeコマンド
$ echo <passwordに設定されている文字列> |base64 -d; echo
```


### ex3
- 以下のyamlを作成し、dbをDeplomentと作成せよ

※MYSQL_ROOT_PASSWORDをex1で設定したsecretsから設定していることに注目すること

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress-mysql
  labels:
    app: wordpress
spec:
  selector:
    matchLabels:
      app: wordpress
      tier: mysql
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: wordpress
        tier: mysql
    spec:
      containers:
      - image: mysql:5.6
        name: mysql
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-pass
              key: password
        ports:
        - containerPort: 3306
          name: mysql
```

### ex4
- 以下の条件でex3のdbのserviceを作成せよ

```
name: wordpress-mysql
port: 3306
type: clusterIP
```

### ex5
- 以下のyamlを修正し、wordpressのDeplomentと作成せよ
- 修正箇所は以下の2ヶ所

```
<修正箇所1> → DBに接続するときのホスト名
<修正箇所2> → ex3を参考にしてex1で設定したsecretsを利用せよ
```


```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
  labels:
    app: wordpress
spec:
  selector:
    matchLabels:
      app: wordpress
      tier: frontend
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: wordpress
        tier: frontend
    spec:
      containers:
      - image: wordpress:5.2-apache
        name: wordpress
        env:
        - name: WORDPRESS_DB_HOST
          value: <修正箇所1>
        - name: WORDPRESS_DB_PASSWORD
          <修正箇所2>
        ports:
        - containerPort: 80
          name: wordpress

```

### ex6
- 以下の条件でex5のwordpressのserviceを作成せよ

```
name: wordpress
port: 80
type: clusterIP
```

### ex7
- 以下の条件でex6で作成したserviceに向けてIngressを作成せよ

```
host: wordpress.local
path: /
pathType: Prefix
```

### ex8
- Laptopのhostを書き換えて、wordpress.localにBrowserで接続せよ
