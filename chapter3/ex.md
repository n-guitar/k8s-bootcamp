# Pod XXXXXXXXXXX

## (前提事項) Kubectlコマンドの補完 & エイリアス
```sh
$ source <(kubectl completion bash)
$ echo "source <(kubectl completion bash)" >> ~/.bashrc
$ alias k=kubectl
$ complete -F __start_kubectl k
```

## (前提事項)kubernetes clusterの情報確認
```sh
# control-plane, workerが各1台以上Readyで存在していること
$ k get nodes
NAME            STATUS   ROLES                  AGE   VERSION
master-node     Ready    control-plane,master   16h   v1.22.10
worker-node01   Ready    worker                 16h   v1.22.10
```


## Podの作成と確認

```sh
# Podの確認(default namespace)
$ k get pod

# Podの作成(コマンド)
$ k run test-pod --image=nginx:alpine

# 結果の例：作成中(ContainerCreating)
$ k get pod
NAME       READY   STATUS              RESTARTS   AGE
test-pod   0/1     ContainerCreating   0          13s
# 結果の例：実行中(Running)
$ k get pod
NAME       READY   STATUS    RESTARTS   AGE
test-pod   1/1     Running   0          41s

# どのnodeで実行されているか確認
$ k get pod -o wide

# Podの詳細確認
$ k describe pod test-pod

# Podのログ確認
$ k logs test-web

# Pod定義の編集
# 変更前確認
$ k get pod --show-labels
# 変更 labelsをtest-podからedit-podに変更する
# labels:
    # run: test-pod -> run: edit-pod
$ k edit pod test-pod
# 変更後確認
$ k get pod --show-labels

# Podの実行中のコンテナへのシェルを取得する
$ k exec test-pod -- ps aux
$ k exec test-pod -- ls /usr/share/nginx/html
$ k exec test-pod -- cat /usr/share/nginx/html/index.html
$ k exec test-pod -- curl localhost
# コンテナへログインする
$ k exec -it test-pod -- /bin/sh
# コンテナ内で実行
curl localhost
exit # コンテナ内のシェルを終了する


# Podの削除
$ k delete pod test-pod
# 確認
$ k get pod
```

## Podの作成(yaml)
```sh
# yamlの作成
# 以下のyaml定義をコピーしてyamlファイルを作成する
$ vi /tmp/myapp-pod.yaml
```

- myapp-pod.yaml
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: myapp-pod
  labels:
    app: myapp
spec:
  containers:
  - name: myapp-container
    image: busybox
    command: ['sh', '-c', 'echo Hello Kubernetes! && sleep 3600']
```

```sh
# yamlの適応
$ k apply -f /tmp/myapp-pod.yaml

# 確認
$ k get pod -l app=myapp
$ k logs myapp-pod
Hello Kubernetes!

# yamlの編集
# labelsに"env: dev"を追加する
#   labels:
#     app: myapp
#     env: dev
$ vi /tmp/myapp-pod.yaml
# yamlの適応
$ k apply -f /tmp/myapp-pod.yaml
# 確認
$ k get pod -l app=myapp
$ k get pod -l env=dev

# Podの削除
# --grace-period=0 --force 強制削除
# 強制削除がPodの削除に成功したかどうかに関係なく、apiserverから名前をすぐに解放する。
$ k delete --grace-period=0 --force -f /tmp/myapp-pod.yaml
# 確認
$ k get pod -l app=myapp
$ k get pod -l env=dev
```

# multi container Pod

```sh
# yamlの作成
# 以下のyaml定義をコピーしてyamlファイルを作成する
$ vi /tmp/mc-pod.yaml
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: mc1
  labels:
    app: mcpod
spec:
  volumes:
  - name: html
    emptyDir: {}
  containers:
  - name: 1st
    image: nginx:alpine
    volumeMounts:
    - name: html
      mountPath: /usr/share/nginx/html
  - name: 2nd
    image: alpine
    volumeMounts:
    - name: html
      mountPath: /html
    command: ["/bin/sh", "-c"]
    args:
      - while true; do
          date >> /html/index.html;
          sleep 1;
        done
```

```sh
# yamlの適応
$ k apply -f /tmp/mc-pod.yaml
# 確認
$ k get pod -l app=mcpod

# それぞれのコンテナにshellを取得する
$ k exec mc1 -c 1st -- cat /usr/share/nginx/html/index.html
$ k exec mc1 -c 2nd -- /bin/cat /html/index.html

# 削除
$ k delete -f /tmp/mc-pod.yaml
# 確認
$ k get pod -l app=mcpod
```

# init container Pod
```sh
# yamlの作成
# 以下のyaml定義をコピーしてyamlファイルを作成する
$ vi /tmp/init-pod.yaml
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: init-pod
  labels:
    app: init-pod
spec:
  containers:
  - name: nginx
    image: nginx:alpine
    ports:
    - containerPort: 80
    volumeMounts:
    - name: workdir
      mountPath: /usr/share/nginx/html
  # These containers are run during pod initialization
  initContainers:
  - name: install
    image: busybox:1.28
    command:
    - wget
    - "-O"
    - "/work-dir/index.html"
    - https://raw.githubusercontent.com/n-guitar/k8s-bootcamp/develop/chapter3/object/init.html
    volumeMounts:
    - name: workdir
      mountPath: "/work-dir"
  dnsPolicy: Default
  volumes:
  - name: workdir
    emptyDir: {}
```

```sh
# yamlの適応
$ k apply -f /tmp/init-pod.yaml
# 確認
$ k get pod -l app=init-pod

# shellを取得する
$ k exec init-pod -- curl localhost|grep Hello

# (OPTION)
# serviceは別途実施します
# nodeportで公開
$ k expose pod/init-pod --type="NodePort" --port 80
# port確認
$ k describe svc init-demo |grep NodePort:
# ブラウザでnodeのIPでaccess
# 例: http://192.168.200.11:30008/

# 削除
$ k delete -f /tmp/init-pod.yaml
# 確認
$ k get pod -l app=init-pod
```

# ReplicaSets
```sh
# yamlの作成
# 以下のyaml定義をコピーしてyamlファイルを作成する
$ vi /tmp/rs-pod.yaml
```

```yaml
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: rs-pod
  labels:
    app: rs-pod
spec:
  # modify replicas according to your case
  replicas: 3
  selector:
    matchLabels:
      app: rs-pod
  template:
    metadata:
      labels:
        app: rs-pod
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
```

```sh
# yamlの適応
$ k apply -f /tmp/rs-pod.yaml
# 確認
$ k get rs -l app=rs-pod
# 詳細確認
$ k describe rs rs-pod
# Podの確認
$ k get pod -l app=rs-pod

# 任意のPodを削除する
# 以下のコマンドで取得したPod名を利用
$ k get pod -l app=rs-pod
# 例
$ k delete pod rs-pod-2xhf2
# 確認
# Podはいくつになっているか？
$ k get rs -l app=rs-pod
$ k get pod -l app=rs-pod

# replicasの変更
# replicas: 3 → replicas: 4に変更する
$ vi /tmp/rs-pod.yaml
# yamlの適応
$ k apply -f /tmp/rs-pod.yaml
# 確認
# Podはいくつになっているか？
$ k get pod -l app=rs-pod

# コマンドで変更
$ k scale --replicas=2 rs/rs-pod
# 確認
$ k get rs -l app=rs-pod
$ k get pod -l app=rs-pod

# 削除
$ k delete -f  /tmp/rs-pod.yaml
# 確認
$ k get rs -l app=rs-pod
$ k get pod -l app=rs-pod
```

# Deployments
- Deploymentsの作成と操作
```sh
# yamlの作成
# 以下のyaml定義をコピーしてyamlファイルを作成する
$ vi /tmp/deploy-pod.yaml
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  labels:
    app: deploy-pod
spec:
  replicas: 4
  selector:
    matchLabels:
      app: deploy-pod
  template:
    metadata:
      labels:
        app: deploy-pod
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
```

```sh
# yamlの適応
$ k apply -f /tmp/deploy-pod.yaml
# 確認
$ k get deploy -l app=deploy-pod
# 詳細確認
# Annotations、Replicas、StrategyType、RollingUpdateStrategyは何になっているか？
$ k describe deploy nginx-deployment
# Replicasの確認
$ k get rs -l app=deploy-pod
# Podの確認
$ k get pod -l app=deploy-pod

# 任意のPodを削除する
# 以下のコマンドで取得したPod名を利用
$ k get pod -l app=deploy-pod
# 例
$ k delete pod nginx-deployment-fb4d8cd56-mdht2
# 確認
# Podはいくつになっているか？
$ k get pod -l app=deploy-pod


# yamlでimageを変更
# nginx:alpine → nginx:1.22.0-alpine
$ vi /tmp/deploy-pod.yaml
# yamlの適応
$ k apply -f /tmp/deploy-pod.yaml
# すぐに確認するとRollingUpdateStrategyのルールでpodが起動＆削除されている
$ k get pod -l app=deploy-pod
# 詳細確認
# Imageが変更されているか、Annotationsは？
$ k describe deploy nginx-deployment

# rollout
# 変更履歴が出る
# ※--record=trueがしれっと公式Docから削除されていた。
# REVISIONはいくつあるか？
$ k rollout history deployment/nginx-deployment
# undo
$ k rollout undo deployment/nginx-deployment --to-revision=1
# 確認
k get pod -l app=deploy-pod
$ k describe deploy nginx-deployment

# 削除
$ k delete -f  /tmp/deploy-pod.yaml
# 確認
$ k get deploy -l app=deploy-pod
$ k get rs -l app=deploy-pod
$ k get pod -l app=deploy-pod
```

- Deploymentsのコマンドによる作成
```sh
# 以下のコマンドでDeploymentを作成できる
$ k create deployment deploy-ex-pod --image=nginx:alpine --replicas=2

# 確認
$ k get deploy -l app=deploy-ex-pod

# 削除
$ k delete deploy deploy-ex-pod
$ k get deploy -l app=deploy-ex-pod

# 雛形の作成
$ k create deployment deploy-ex-pod --image=nginx:alpine --replicas=2 --dry-run=client -o yaml
# ファイル出力
$ k create deployment deploy-ex-pod --image=nginx:alpine --replicas=2 --dry-run=client -o yaml > /tmp/deploy-ex-pod.yaml
$ ls -l /tmp/deploy-ex-pod.yaml

# 適応
$ k apply -f /tmp/deploy-ex-pod.yaml
# 確認
$ k get deploy -l app=deploy-ex-pod

# 削除
$ k delete deploy deploy-ex-pod
$ k get deploy -l app=deploy-ex-pod
```



## 練習問題

### ex1
- 名前を"ex1-pod"、imageを"nginx:1.21-alpine"でPodを作成せよ

### ex2
- 事前作業
```sh
$ curl -sL https://raw.githubusercontent.com/n-guitar/k8s-bootcamp/develop/chapter3/object/ex_run.sh | bash -s ex2 develop
```

#### ex2-1
- 名前が"ex2-pod-xxxx"(xxxは読み替え)、のPodはいくつあるか？

#### ex2-2
- "ex2-pod-xxxx"(xxxは読み替え)、のPodで利用されているcontainer imageはなにか？

### ex3
- 事前作業
```sh
$ curl -sL https://raw.githubusercontent.com/n-guitar/k8s-bootcamp/develop/chapter3/object/ex_run.sh | bash -s ex3 develop
```

#### ex3-1
- 名前が"ex3-pod"はいくつcontainerが含まれているか？

#### ex3-2
- "ex3-pod"(xxxは読み替え)、のPodで利用されているcontainer imageはなにか？全て答えよ。

#### ex3-3
- "ex3-pod"(xxxは読み替え)、のPodで利用されているcontainerのStateはなにか？全て答えよ。

#### ex3-4
- "ex3-pod"(xxxは読み替え)、のPodで利用されているcontainer "ex3-pod-httpd"はなぜ実行に失敗しているか？

#### ex3-5
- "ex3-pod"(xxxは読み替え)、の定義を修正し、container "ex3-pod-httpd"のエラーを解消せよ。

### ex4
- 以下のReplicaSetの定義は一部誤りがあり、kubectl applyするとエラーになります。
- /tmp/rc-ex.yamlというファイル名で定義を修正し、kubectl applyせよ。

- c-ex.yaml
```yaml
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: ex4-pod
  labels:
    app: ex4-pod
spec:
  # modify replicas according to your case
  replicas: 3
  selector:
    matchLabels:
      app: ex4-pod
  template:
    metadata:
      labels:
        app: nginx-pod
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
```

### ex5
- 名前を"ex5-pod"、imageを"nginx:1.21-alpine"、replicas 2でdeploymentを作成せよ
