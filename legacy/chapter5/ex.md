# Schedulingの操作

## (前提事項) Kubectlコマンドの補完 & エイリアス
```sh
$ source <(kubectl completion bash)
$ echo "source <(kubectl completion bash)" >> ~/.bashrc
$ alias k=kubectl
$ complete -F __start_kubectl k
```

## (前提事項)kubernetes clusterの情報確認
!! このChapterではworker nodeが2台以上あることが望ましいです。

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

## 様々なスケジューリング

### kube-schedulerの確認
- 以下を一読しましょう。
  - https://v1-22.docs.kubernetes.io/ja/docs/concepts/scheduling-eviction/kube-scheduler/

### nodeName
※制約があるためあまり使用しない。<br>
※後述するnodeSelectorやTaintsより優先される、またMaintenance時に利用するcordon/uncordonも無視する。
<br><br>

- 以下のDeploymentを作成し、applyする

```sh
# yamlの作成
# 以下のyaml定義をコピーしてyamlファイルを作成する
$ vi /tmp/nn-pod.yaml
$ k apply -f /tmp/nn-pod.yaml
```

- nodeName: worker-node01を指定するDeployment
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: nn-pod
  name: nn-pod
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nn-pod
  template:
    metadata:
      labels:
        app: nn-pod
    spec:
      containers:
      - image: nginx:alpine
        name: nginx
      nodeName: worker-node01
```

```sh
# 以下の用にworker nodeが複数ある状態で、Podをいくら削除してもnodeNaneに一致するnodeのスケジュールされる
$ k get nodes
NAME            STATUS   ROLES                  AGE     VERSION
master-node     Ready    control-plane,master   3h23m   v1.22.10
worker-node01   Ready    worker                 3h12m   v1.22.10
worker-node02   Ready    worker                 3h3m    v1.22.10

# 削除と確認を繰り返す
$ k delete pod -l app=nn-pod && k get pod -l app=nn-pod -o wide
NAME                     READY   STATUS    RESTARTS   AGE   IP              NODE            NOMINATED NODE   READINESS GATES
nn-pod-cff9f8745-gfvvl   1/1     Running   0          14s   10.244.87.195   worker-node01   <none>           <none>

# Deployment削除
$ k delete -f /tmp/nn-pod.yaml
```
<br><br>

### nodeSelector
Nodeを選択するための、最も簡単で推奨されている手法<br>
Nodeのlabelを利用して、スケジュールをコントロールする

- Nodeのlabel追加

```sh
# labelの確認
# ディストリビューションやクラウド環境によって様々なlabelがデフォルトで付与されている場合がある
$ k get nodes --show-labels
NAME            STATUS   ROLES                  AGE     VERSION    LABELS
master-node     Ready    control-plane,master   3h45m   v1.22.10   beta.kubernetes.io/arch=amd64,beta.kubernetes.io/os=linux,kubernetes.io/arch=amd64,kubernetes.io/hostname=master-node,kubernetes.io/os=linux,node-role.kubernetes.io/control-plane=,node-role.kubernetes.io/master=,node.kubernetes.io/exclude-from-external-load-balancers=
worker-node01   Ready    worker                 3h34m   v1.22.10   beta.kubernetes.io/arch=amd64,beta.kubernetes.io/os=linux,kubernetes.io/arch=amd64,kubernetes.io/hostname=worker-node01,kubernetes.io/os=linux,node-role.kubernetes.io/worker=worker
worker-node02   Ready    worker                 3h25m   v1.22.10   beta.kubernetes.io/arch=amd64,beta.kubernetes.io/os=linux,kubernetes.io/arch=amd64,kubernetes.io/hostname=worker-node02,kubernetes.io/os=linux,node-role.kubernetes.io/worker=worker

# describeコマンドで個別に確認する
$ k describe node worker-node01

# 任意のLabelを付与
# kubectl label nodes <node-name> <label-key>=<label-value>
$ k label nodes worker-node01 env=dev
$ k label nodes worker-node02 env=stg

# 確認
$ k get nodes -l env=dev
NAME            STATUS   ROLES    AGE     VERSION
worker-node01   Ready    worker   3h39m   v1.22.10

# 確認
$ k get nodes -l env=stg
NAME            STATUS   ROLES    AGE     VERSION
worker-node02   Ready    worker   3h29m   v1.22.10

# describeコマンドで個別に確認する
$ k describe node worker-node01
$ k describe node worker-node02
```
<br>

- PodへのnodeSelectorフィールドの追加

  - 以下のDeploymentを作成し、applyする

```sh
# yamlの作成
# 以下のyaml定義をコピーしてyamlファイルを作成する
$ vi /tmp/ns-dev-pod.yaml
$ k apply -f /tmp/ns-dev-pod.yaml
```

  - labelにenv=devがついているnodeにスケジュールする
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: ns-dev-pod
  name: ns-dev-pod
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ns-dev-pod
  template:
    metadata:
      labels:
        app: ns-dev-pod
    spec:
      containers:
      - image: nginx:alpine
        name: nginx
      nodeSelector:
        env: dev
```

```sh
# 確認
$ k get nodes -l env=dev
NAME            STATUS   ROLES    AGE     VERSION
worker-node01   Ready    worker   3h49m   v1.22.10

# worker-node01にスケジュールされる
$ k get pod -l app=ns-dev-pod -o wide
NAME                          READY   STATUS    RESTARTS   AGE    IP              NODE            NOMINATED NODE   READINESS GATES
ns-dev-pod-6b985cf457-nx9t8   1/1     Running   0          4m3s   10.244.87.200   worker-node01   <none>           <none>
ns-dev-pod-6b985cf457-rqqrk   1/1     Running   0          4m3s   10.244.87.201   worker-node01   <none>           <none>

# 複数回繰り返して確認する
$ k delete pod -l app=ns-dev-pod && k get pod -l app=ns-dev-pod -o wide

# Deployment削除
# nodeのlabelは後で使うためそのままにしておく
$ k delete -f /tmp/ns-dev-pod.yaml
```

### TaintsとTolarations
- Taints<br>
Nodeに対して設定する。<br>
直訳すると汚れ、腐敗。<br>
→Podを排出させる役割や、汚れを許容しない・耐性がないPodをスケジュールさせない動きをする。<br>
Podはきれい好きなので、汚れたNodeでは起動したくない<br>

- Tolarations<br>
Podに対して設定する。<br>
Tolarationを直訳すると寛容、黙認。<br>
→特定のTaints(汚れ・腐敗)に対してスケジュールすることを認める。汚れに対して耐性を持つようなイメージ<br>
!! ただし、耐性があるだけで、そのTaintsがついたNodeへ必ずスケジューリングされるとは限らない !!

<br>

- Nodeにtaintを付与

```sh
# worker-node01, worker-node02いずれも汚す
# kubectl taint nodes  <node-name>  <key>=<value>:<NoSchedule, PreferNoSchedule or NoExecute.>
$ k taint nodes worker-node01 cpu=lowspec:NoSchedule
$ k taint nodes worker-node02 cpu=lowspec:NoSchedule

# 確認
$ k describe nodes |grep Taints
Taints:             node-role.kubernetes.io/master:NoSchedule
Taints:             cpu=lowspec:NoSchedule
Taints:             cpu=lowspec:NoSchedule
```


<br>

- Pod配置
  - 以下のDeploymentを作成し、applyする

```sh
# yamlの作成
# 以下のyaml定義をコピーしてyamlファイルを作成する
$ vi /tmp/tola-pod.yaml
$ k apply -f /tmp/tola-pod.yaml
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: tola-pod
  name: tola-pod
spec:
  replicas: 1
  selector:
    matchLabels:
      app: tola-pod
  template:
    metadata:
      labels:
        app: tola-pod
    spec:
      containers:
      - image: nginx:alpine
        name: nginx
```

```sh
# 確認
# Pending状態のママになる
$ k get pod -l app=tola-pod
NAME                       READY   STATUS    RESTARTS   AGE
tola-pod-c5855894f-nctkk   0/1     Pending   0          25s

# Eventsを確認する
$ k describe pod -l app=tola-pod
```

```sh
# 以下の用にyamlを修正し、applyする
$ vi /tmp/tola-pod.yaml
$ k apply -f /tmp/tola-pod.yaml
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: tola-pod
  name: tola-pod
spec:
  replicas: 1
  selector:
    matchLabels:
      app: tola-pod
  template:
    metadata:
      labels:
        app: tola-pod
    spec:
      containers:
      - image: nginx:alpine
        name: nginx
      tolerations:
      - key: "cpu"
        operator: "Equal"
        value: "lowspec"
        effect: "NoSchedule"
```

```sh
# 確認
# スケジュールされている
$ k get pod -l app=tola-pod
NAME                        READY   STATUS    RESTARTS   AGE
tola-pod-584c849497-k9dnv   1/1     Running   0          11s

# Deploymentの削除
$ k delete -f /tmp/tola-pod.yaml

# Taintsの削除
$ k taint nodes worker-node01 cpu=lowspec:NoSchedule-
$ k taint nodes worker-node02 cpu=lowspec:NoSchedule-

# 確認
$ k describe nodes |grep Taints
Taints:             node-role.kubernetes.io/master:NoSchedule
Taints:             <none>
Taints:             <none>
```
<br><br>

### AffinityとAntiAffinity
PodをKubernetesクラスター内の特定のノードにスケジュールさせる方法。<br>
nodeSelectorより高度な条件を記述できる。<br>


#### nodeAffinity
NodeのラベルによってPodがどのNodeにスケジュールされるかを制限する。<br>

```sh
# labelの確認
# envというlabel keyがついているnodeを表示
$ k get nodes -l env --show-labels
NAME            STATUS   ROLES    AGE     VERSION    LABELS
worker-node01   Ready    worker   5h3m    v1.22.10   beta.kubernetes.io/arch=amd64,beta.kubernetes.io/os=linux,env=dev,kubernetes.io/arch=amd64,kubernetes.io/hostname=worker-node01,kubernetes.io/os=linux,node-role.kubernetes.io/worker=worker
worker-node02   Ready    worker   4h53m   v1.22.10   beta.kubernetes.io/arch=amd64,beta.kubernetes.io/os=linux,env=stg,kubernetes.io/arch=amd64,kubernetes.io/hostname=worker-node02,kubernetes.io/os=linux,node-role.kubernetes.io/worker=worker
```

- 以下のDeploymentを作成し、applyする

```sh
# yamlの作成
# 以下のyaml定義をコピーしてyamlファイルを作成する
$ vi /tmp/naffinity-pod.yaml
$ k apply -f /tmp/naffinity-pod.yaml
```

- nodeAffinityを設定
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: naffinity-pod
  name: naffinity-pod
spec:
  replicas: 2
  selector:
    matchLabels:
      app: naffinity-pod
  template:
    metadata:
      labels:
        app: naffinity-pod
    spec:
      containers:
      - image: nginx:alpine
        name: nginx
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: env
                operator: In
                values:
                - dev
```

```sh
# 確認
# env=devのlabelがついたnodeで稼働していることがわかる
$ k get pod -l app=naffinity-pod -o wide
NAME                             READY   STATUS    RESTARTS   AGE   IP              NODE            NOMINATED NODE   READINESS GATES
naffinity-pod-75c4d4c5c8-7v4vq   1/1     Running   0          21s   10.244.87.206   worker-node01   <none>           <none>
naffinity-pod-75c4d4c5c8-cdc6t   1/1     Running   0          21s   10.244.87.207   worker-node01   <none>           <none>

# 削除
$ k delete -f /tmp/naffinity-pod.yaml
```
<br>

#### podAffinityとpodAntiAffinity
Nodeのラベルではなく、すでにNodeで稼働しているPodのラベルに従ってPodがスケジュールされるNodeを制限する<br>

- 以下のDeploymentを作成し、applyする

```sh
# yamlの作成
# 以下のyaml定義をコピーしてyamlファイルを作成する
$ vi /tmp/frontend-pod.yaml
$ k apply -f /tmp/frontend-pod.yaml
```
- app=frontend-podという名前がついているpodを作成
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: frontend-pod
  name: frontend-pod
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend-pod
  template:
    metadata:
      labels:
        app: frontend-pod
    spec:
      containers:
      - image: nginx:alpine
        name: nginx
```

```sh
# 確認
# どのnodeで稼働しててもOK
$ k get pod -l app=frontend-pod -o wide
NAME                            READY   STATUS    RESTARTS   AGE   IP             NODE            NOMINATED NODE   READINESS GATES
frontend-pod-79767bcc99-z8nfv   1/1     Running   0          7s    10.244.158.6   worker-node02   <none>           <none>
```
<br>

- podAffinityの付与

- 以下のDeploymentを作成し、applyする

```sh
# yamlの作成
# 以下のyaml定義をコピーしてyamlファイルを作成する
$ vi /tmp/paffinity-pod.yaml
$ k apply -f /tmp/paffinity-pod.yaml
```
- app=frontend-podという名前がついているpodが稼働しているnode上で稼働させるPodを作成
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: paffinity-pod
  name: paffinity-pod
spec:
  replicas: 2
  selector:
    matchLabels:
      app: paffinity-pod
  template:
    metadata:
      labels:
        app: paffinity-pod
    spec:
      containers:
      - image: nginx:alpine
        name: nginx
      affinity:
        podAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - frontend-pod
            topologyKey: "kubernetes.io/hostname"
```

```sh
# 確認
# app=frontend-podのlabelがついているPodと同じnodeで稼働していることがわかる
$ k get pod -o wide -l 'app in (frontend-pod, paffinity-pod)' --show-labels
NAME                            READY   STATUS    RESTARTS   AGE     IP              NODE            NOMINATED NODE   READINESS GATES   LABELS
frontend-pod-79767bcc99-w2ffp   1/1     Running   0          5m48s   10.244.158.15   worker-node02   <none>           <none>            app=frontend-pod,pod-template-hash=79767bcc99
paffinity-pod-cbfd7d49f-54bfq   1/1     Running   0          10m     10.244.158.7    worker-node02   <none>           <none>            app=paffinity-pod,pod-template-hash=cbfd7d49f
paffinity-pod-cbfd7d49f-wlkvc   1/1     Running   0          10m     10.244.158.8    worker-node02   <none>           <none>            app=paffinity-pod,pod-template-hash=cbfd7d49f

# 削除
$ k delete -f /tmp/frontend-pod.yaml
$ k delete -f /tmp/paffinity-pod.yaml
```
<br><br>

### DaemonSet
全て(またはいくつか)のNodeが単一のPodのコピーを稼働させることを保証する。<br>

- 以下のDaemonSetを作成し、applyする

```sh
# yamlの作成
# 以下のyaml定義をコピーしてyamlファイルを作成する
$ vi /tmp/ds-pod.yaml
$ k apply -f /tmp/ds-pod.yaml
```
- masterを含む全てのnodeで稼働するPodを作成する
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  labels:
    app: ds-pod
  name: ds-pod
spec:
  selector:
    matchLabels:
      app: ds-pod
  template:
    metadata:
      labels:
        app: ds-pod
    spec:
      containers:
      - image: nginx:alpine
        name: nginx
      tolerations:
      - operator: Exists
```

```sh
# 確認
$ k get ds
NAME     DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
ds-pod   3         3         3       3            3           <none>          5s
$ k get pod -l app=ds-pod -o wide
NAME           READY   STATUS    RESTARTS   AGE   IP              NODE            NOMINATED NODE   READINESS GATES
ds-pod-6gkgf   1/1     Running   0          51s   10.244.87.208   worker-node01   <none>           <none>
ds-pod-6nwv4   1/1     Running   0          51s   10.244.158.16   worker-node02   <none>           <none>
ds-pod-xx6l6   1/1     Running   0          51s   10.244.77.140   master-node     <none>           <none>

# 削除
$ k delete -f /tmp/ds-pod.yaml
```


## 練習問題

### ex1
- nodeNameを利用してworker-node01にスケジュールするDeploymentを以下の条件で作成せよ。
```
replicas: 2
name: ex1-pod
image: nginx:alpine
```

### ex2

#### ex2-1
- worker-node01に以下の条件でlabelを付与せよ
```
exam=ex2
```

#### ex2-2
- ex2-1で付与したlabelを利用して、スケジュールするDeploymentを以下の条件で作成せよ。
```
replicas: 2
name: ex2-pod
image: nginx:alpine
```


### ex3
- 事前作業
```sh
$ curl -sL https://raw.githubusercontent.com/n-guitar/k8s-bootcamp/main/chapter5/object/ex_run.sh | bash -s ex3 main
```

#### ex3-1
- worker-node01で稼働しているPodは何個存在しているか？<br>
※default namespaceのみとする

#### ex3-2
- worker-node01にcpu=lowspec:NoExecuteとし、Taintを付与し、 ex3-1で確認したworker-node01で稼働しているPodがどうなったか答えよ。

#### ex3-3
- worker-node01のcpu=lowspec:NoExecuteのTaintを削除し、 worker-node01、worker-node02にそれぞれ、cpu=lowspec:NoScheduleのTaintをTaintを付与せよ。

#### ex3-4
-  ex3-3で確認したPodがどうなったか答えよ。

#### ex3-5
- cpu=lowspec:NoScheduleを許容するTolerationsを付与したDeploymentを以下の条件で作成せよ。
```
replicas: 2
name: ex3-pod
image: nginx:alpine
```

#### ex3-6
- ex3-3で付与したTaintを削除せよ


## 練習問題(advanced)

### a-ex1
- 事前確認
以下のyamlはnodeAffinityを利用して、env=expのlabelがついているnodeにスケジュールするように定義されている。<br>
しかしながら、env=expのlabelがついているnodeは存在しないため、Pending状態となってしまう。<br>

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: ex4-pod
  name: ex4-pod
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ex4-pod
  template:
    metadata:
      labels:
        app: ex4-pod
    spec:
      containers:
      - image: nginx:alpine
        name: nginx
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: env
                operator: In
                values:
                - exp
```

#### a-ex1-1
- requiredDuringSchedulingIgnoredDuringExecutionではなく、preferredDuringSchedulingIgnoredDuringExecutionに変更し、env=expのlabelがついているnodeがない場合でも他の場所で稼働させる用にyamlを修正し、applyせよ

### a-ex2
- podAntiAffinityを利用して、worker-node01、worker-node02に必ずそれそれ1つずつ稼働するようなDeploymentを以下の条件で作成せよ。
  - ヒント
    - https://kubernetes.io/ja/docs/concepts/scheduling-eviction/assign-pod-node/
    - 自分自身のlabelを利用する

```
replicas: 2
name: aex2-pod
image: nginx:alpine
```


## cleanup
```sh
$ curl -sL https://raw.githubusercontent.com/n-guitar/k8s-bootcamp/main/chapter5/object/ex_run.sh | bash -s delete main
```
