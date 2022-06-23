# Serviceの操作

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


## PodのIPAddressの確認

- Deploymentsの作成
```sh
# yamlの作成
# 以下のyaml定義をコピーしてyamlファイルを作成する
$ vi /tmp/chap4-pod.yaml
```
- 自分自身のpod名を表示するweb pod

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  creationTimestamp: null
  labels:
    app: chap4-pod
  name: chap4-pod
spec:
  replicas: 2
  selector:
    matchLabels:
      app: chap4-pod
  template:
    metadata:
      creationTimestamp: null
      labels:
        app: chap4-pod
    spec:
      containers:
      - image: nginx:alpine
        name: nginx
        volumeMounts:
        - name: workdir
          mountPath: /usr/share/nginx/html
      initContainers:
      - image: busybox:1.28
        name: install
        command: ["/bin/sh", "-c"]
        args:
          - echo $MY_POD_NAME > /work-dir/index.html;
        env:
         - name: MY_POD_NAME
           valueFrom:
             fieldRef:
               fieldPath: metadata.name
        volumeMounts:
        - name: workdir
          mountPath: "/work-dir"
      volumes:
      - name: workdir
        emptyDir: {}
```

```sh
# 適応
$ k apply -f /tmp/chap4-pod.yaml
# 確認
$ k get deploy -l app=chap4-pod
# -o wideでPodに割り当てられたIPを確認する
$ k get pod -l app=chap4-pod -o wide
# 表示例
NAME                         READY   STATUS    RESTARTS   AGE     IP              NODE            NOMINATED NODE   READINESS GATES
chap4-pod-5866486765-ffdfr   1/1     Running   0          3m57s   10.244.87.209   worker-node01   <none>           <none>
chap4-pod-5866486765-pgnhp   1/1     Running   0          3m59s   10.244.87.208   worker-node01   <none>           <none>

# 片方のコンテナへログインする
$ k exec -it <pod名> -c nginx -- /bin/sh
# container内
curl localhost
# それぞれのIPでアクセスし、pod名が帰ってくることを確認する
curl 10.xxx.xxx.xxx
curl 10.xxx.xxx.xxx
exit

# もう一度-o wideでPodに割り当てられたIPを確認する
$ k get pod -l app=chap4-pod -o wide

# podを削除する
$  k delete pod <pod名>

# もう一度-o wideでPodに割り当てられたIPを確認する
$ k get pod -l app=chap4-pod -o wide
# 表示例
# 10.244.87.209のIPがなくなり 10.244.87.210になってしまっていることがわかる。
# PodのIPは不定
NAME                         READY   STATUS    RESTARTS   AGE     IP              NODE            NOMINATED NODE   READINESS GATES
chap4-pod-5866486765-hvlz8   1/1     Running   0          12s     10.244.87.210   worker-node01   <none>           <none>
chap4-pod-5866486765-pgnhp   1/1     Running   0          4h15m   10.244.87.208   worker-node01   <none>           <none>
```

# Serviceの作成と確認
- serviceの作成
```sh
# yamlの作成
# 以下のyaml定義をコピーしてyamlファイルを作成する
$ vi /tmp/chap4-svc.yaml
```
- ClusterIPのServiceを作成

```yaml
apiVersion: v1
kind: Service
metadata:
  creationTimestamp: null
  labels:
    app: chap4-svc
  name: chap4-svc
spec:
  ports:
  - name: 80-80
    port: 80
    protocol: TCP
    targetPort: 80
  selector:
    app: chap4-svc
  type: ClusterIP
status:
  loadBalancer: {}
```

```sh
# 適応
$ k apply -f /tmp/chap4-svc.yaml
# 確認
$ k get svc -l app=chap4-svc
# 詳細確認
$ k describe svc chap4-svc
# 表示例
# Endpoints何も表示されていない
Name:              chap4-svc
Namespace:         default
Labels:            app=chap4-svc
Annotations:       <none>
Selector:          app=chap4-svc
Type:              ClusterIP
IP Family Policy:  SingleStack
IP Families:       IPv4
IP:                10.107.156.8
IPs:               10.107.156.8
Port:              80-80  80/TCP
TargetPort:        80/TCP
Endpoints:         <none>
Session Affinity:  None
Events:            <none>

# PodのLabelを確認する
# Labels:app=chap4-podとなっていることがわかる
$ k describe deploy chap4-pod

# ServiceのSelectorを修正
# selector: app: chap4-svc → chap4-pod
$ vi /tmp/chap4-svc.yaml

# 適応
$ k apply -f /tmp/chap4-svc.yaml
# 詳細確認
$ k describe svc chap4-svc
# 表示例
# EndpointsにPodのIPが表示されていることがわかる
Name:              chap4-svc
Namespace:         default
Labels:            app=chap4-svc
Annotations:       <none>
Selector:          app=chap4-pod
Type:              ClusterIP
IP Family Policy:  SingleStack
IP Families:       IPv4
IP:                10.107.156.8
IPs:               10.107.156.8
Port:              80-80  80/TCP
TargetPort:        80/TCP
Endpoints:         10.244.87.208:80,10.244.87.210:80
Session Affinity:  None
Events:            <none>

# アクセス確認
# 片方のコンテナへログインする
$ k exec -it <pod名> -c nginx -- /bin/sh
# container内
curl chap4-svc
# 複数回実行し、それぞれのPodにアクセスしていることを確認
for i in `seq 1 5` ; do curl chap4-svc ; done;

# 削除
$ k delete -f /tmp/chap4-svc.yaml
$ k delete -f /tmp/chap4-pod.yaml
```

## 練習問題

### ex1
- 事前作業
```sh
$ curl -sL https://raw.githubusercontent.com/n-guitar/k8s-bootcamp/main/chapter4/object/ex_run.sh | bash -s ex1 main
```

#### ex1-1
- serviceはいくつ存在しているか？<br>
※今回特に意識しないがdefault namespaceの場合

#### ex1-2
- "chap4-ex1"のServiceのType、TergetPortはなにか？

#### ex1-3
- "chap4-ex1"のServiceのLabelはいくつあるか？

#### ex1-4
- "chap4-ex1"のServiceのEndpointsはいくつあるか？

### ex2
- 事前作業
```sh
$ curl -sL https://raw.githubusercontent.com/n-guitar/k8s-bootcamp/main/chapter4/object/ex_run.sh | bash -s ex2 main
```

#### ex2-1
- Deploymentはいくつ存在しているか？<br>
※今回特に意識しないがdefault namespaceの場合

#### ex2-2
- Deploymentで利用されているimageはなにか？

#### ex2-3
- このDeploymentに以下の設定でServiceを作成せよ。ただしselectorはDeploymentの定義から確認し、設定せよ

```
Name: my-webapp
Type: NodePort
tergetPort: 8080
port: 8080
nodePort: 30001
selector: <Deploymentの定義から確認>
```

#### ex2-4
- ホストのIPを確認し、ホストのIP:30001でcurlでaccessせよ。(accessできない場合はex2-3の誤りを疑うこと)
```sh
# 例
curl <ホストのIP>:30001
```

## cleanup
```sh
$ curl -sL https://raw.githubusercontent.com/n-guitar/k8s-bootcamp/main/chapter4/object/ex_run.sh | bash -s delete main
```


## 練習問題(advanced)

### a-ex1
- Pod内で名前解決に使われるnameserverは何か答えよ。<br>
※今回特に意識しないが何も指定しない場合。

### a-ex2
- デフォルトで利用できるNodePortのportレンジはなにか答えよ。

### a-ex3
- ClusterIPで利用できるIPレンジはどこで設定しているか答えよ。
