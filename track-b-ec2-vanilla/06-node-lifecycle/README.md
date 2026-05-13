# 06 — Node Lifecycle: 追加 / drain / 障害 / kubelet 再設定

## ゴール
- worker を 1 台 **追加** する (Terraform `worker_count` を増やす → join)
- `cordon` / `drain` の挙動と **PodDisruptionBudget (PDB)** が drain を抑止する様子を観察
- EC2 を `StopInstances` で **強制障害** → Pod が別 Node に migrate する流れを確認
- kubelet 設定を `KubeletConfiguration` drop-in で書き換え、systemd で reload
- (発展) **In-place Pod Resize** (v1.33 で beta) を試す

---

## 🤔 なぜ必要？ (ストーリー)

> 本番運用に出ると、「Node を 1 台追加する」「ハードウェア障害で Node が死んだ」「Node の kubelet 設定を 1 つだけ変えたい」が日常的に起きる。
>
> マネージドだと "Node Group の desired を +1" でだいたい片付くが、その内側で起きているのは:
> - **EC2 を起動 → cloud-init で k8s パッケージ install → kubeadm join**
> - **Node 死亡 → controller-manager が `NodeNotReady` で taint → Pod を別 Node に reschedule**
> - **Node を退避 → drain で Pod を立ち退かせ、PDB を尊重しながら新 Node へ**
>
> "**Node は使い捨て**" という前提が k8s の根底にあり、ここを身体で覚えるのが本章。

## ✨ 面白いポイント (設計)

### 1. **Node Controller の障害検知タイムライン**

```
Node が応答しない (kubelet が apiserver に PostStatus しない)
    ↓ 40s (node-monitor-grace-period の default)
NotReady に遷移
    ↓ 5min (default-not-ready-toleration-seconds)
Pod に `NoExecute` taint が効き始める
    ↓
Pod が evict されて別 Node に re-schedule
```

> **痺れ所:** "Node 死亡から **約 5〜6 分** で Pod が他に動く" は、誰も明示的に書いていないが**全社共通の経験則**。
> その出所がこの timeline。Tolerations で `tolerationSeconds: 30` を明示すれば数十秒に縮められる。

### 2. **drain は "**eviction API**" を 1 Pod ずつ叩いている**

```
kubectl drain
   ↓
for each Pod on the node:
   POST /api/v1/namespaces/{ns}/pods/{name}/eviction   ← PDB を見る admission
   ↓ PDB を満たさなければ 429 Too Many Requests
   ↓ ループ retry
```

= drain は **graceful shutdown 一括起動の syntactic sugar**。

> **痺れ所:** PDB は **eviction にだけ効く**。`kubectl delete pod` には効かない。
> "**人が手で消す** は PDB を無視するが、**Node を退避する** は PDB を尊重する" という非対称が、本番運用の事故防止に効く。

### 3. **kubelet config は `--config` ファイル + drop-in が最強**

旧来の `KUBELET_EXTRA_ARGS=` 行を編集するスタイルは消えつつあり、`KubeletConfiguration` (v1beta1) を YAML で書く方式が標準。

```
/var/lib/kubelet/config.yaml             ← kubeadm が置く本体
/etc/systemd/system/kubelet.service.d/   ← systemd drop-in
```

## 😱 あるある罠

- **`drain --force` を脳死で付ける**: bare Pod (Deployment 配下でない) を強制削除する。データロスのリスク
- **PDB を設定し忘れ**: drain が一瞬で全 Pod を落とす。本番では **PDB は必須**
- **`StopInstances` でテストして起こし忘れ**: 翌朝コストに気付く。**`StartInstances`** で戻すか destroy
- **kubelet config を直接編集して `kubeadm` 管理と乖離**: 次回 upgrade で上書きされる。drop-in で
- **Node 追加で AMI が違うと挙動が変わる**: AMI を data source 化してあるが、Canonical の新 AMI が出ると微妙に差が出ることも

## やること

### 0. 準備

```bash
export KUBECONFIG=$PWD/../02-kubeadm-bootstrap/kubeconfig
kubectl get nodes
# 3 Node (cp + worker × 2) が Ready

cd ../01-terraform-vpc-ec2/terraform
KEY=~/.ssh/k8s-bootcamp
```

### 1. worker を 1 台追加

```bash
# terraform.tfvars の worker_count を 2 → 3 に変更
terraform apply -var 'worker_count=3' -auto-approve

NEW_WORKER=$(terraform output -json worker_public_ips | jq -r '.[2]')
echo "new worker: $NEW_WORKER"
```

cloud-init を待ってから join:

```bash
ssh -i $KEY ubuntu@$NEW_WORKER 'cloud-init status --wait'

CP=$(terraform output -raw cp_public_ip)
JOIN=$(ssh -i $KEY ubuntu@$CP 'sudo kubeadm token create --print-join-command')
ssh -i $KEY ubuntu@$NEW_WORKER "sudo $JOIN"

cd -
kubectl get nodes
# 4 Node に増えている
```

### 2. PDB ありの Deployment を立てる

`manifests/demo-with-pdb.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata: {name: ch06}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: hello, namespace: ch06}
spec:
  replicas: 4
  selector: {matchLabels: {app: hello}}
  template:
    metadata: {labels: {app: hello}}
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        seccompProfile: {type: RuntimeDefault}
      containers:
        - name: c
          image: nginxdemos/hello:plain-text
          ports: [{containerPort: 80}]
          securityContext:
            allowPrivilegeEscalation: false
            capabilities: {drop: ["ALL"]}
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: {name: hello-pdb, namespace: ch06}
spec:
  minAvailable: 3
  selector: {matchLabels: {app: hello}}
```

```bash
kubectl apply -f manifests/demo-with-pdb.yaml
kubectl -n ch06 get pod -o wide
# 4 Pod が複数 Node に分散
```

### 3. drain で PDB が効くのを観察

最も Pod が乗っている worker を選んで drain:

```bash
NODE=$(kubectl -n ch06 get pod -o wide | awk 'NR>1 {print $7}' | sort | uniq -c | sort -nr | head -1 | awk '{print $2}')
echo "draining $NODE"

kubectl cordon $NODE
kubectl drain $NODE --ignore-daemonsets --delete-emptydir-data
# minAvailable=3 を割り込みそうになると drain は 1 Pod ずつ慎重に進む
# 別 worker で Pod が立ち上がってから次を evict、を繰り返す
```

別 terminal で:

```bash
kubectl -n ch06 get pod -o wide --watch
```

drain 完了後:

```bash
kubectl get nodes
# 該当 node が SchedulingDisabled
kubectl uncordon $NODE
```

### 4. Node 障害をシミュレーション (StopInstances)

```bash
cd ../01-terraform-vpc-ec2/terraform
# 1 台の worker を選んで止める
W_PUB=$(terraform output -json worker_public_ips | jq -r '.[1]')
W_ID=$(aws ec2 describe-instances \
  --filters "Name=ip-address,Values=$W_PUB" \
  --query 'Reservations[].Instances[].InstanceId' --output text)
echo "stopping $W_ID"
aws ec2 stop-instances --instance-ids $W_ID
cd -
```

経過を観察 (別 terminal):

```bash
kubectl get nodes --watch
# Ready → NotReady (約 40 秒)

kubectl -n ch06 get pod -o wide --watch
# 約 5 分後、Pod が別 Node に re-schedule される
```

時間が惜しければ taint を手で押し付ける手も:

```bash
kubectl taint node <NotReadyNode> node.kubernetes.io/unreachable:NoExecute --overwrite
# → Pod が即 evict
```

Node を戻す:

```bash
aws ec2 start-instances --instance-ids $W_ID
# しばらくすると Ready に戻る (kubelet が自動再接続)
```

> **AWS 料金注意:** stop しても EBS の課金は残ります。stop を放置するくらいなら destroy。

### 5. kubelet config を drop-in で書き換える

例: `seccompDefault: true` を全 Pod に効かせたい。

```bash
ssh -i $KEY ubuntu@$NEW_WORKER bash <<'EOF'
set -e
sudo mkdir -p /etc/systemd/system/kubelet.service.d
cat <<'CONF' | sudo tee /etc/systemd/system/kubelet.service.d/20-seccomp.conf
[Service]
Environment="KUBELET_EXTRA_ARGS=--seccomp-default=true"
CONF
sudo systemctl daemon-reload
sudo systemctl restart kubelet
EOF

# 反映確認
kubectl describe node $(ssh -i $KEY ubuntu@$NEW_WORKER 'hostname') | grep -A1 -i seccomp || true
ssh -i $KEY ubuntu@$NEW_WORKER 'systemctl status kubelet --no-pager | head -20'
```

> 本番運用では `KubeletConfiguration` ファイルを kubeadm の `nodeRegistration.kubeletExtraArgs` 経由で配るのが望ましい。drop-in は **その場限り** の調整向き。

### 6. (発展) In-place Pod Resize

v1.33 で **beta**。Pod を再作成せずに CPU / memory を変更できる。

`manifests/resizable.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata: {name: resizable, namespace: ch06}
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    seccompProfile: {type: RuntimeDefault}
  containers:
    - name: c
      image: busybox:1.36
      command: ["sleep", "9999"]
      resources:
        requests: {cpu: "100m", memory: "64Mi"}
        limits:   {cpu: "200m", memory: "128Mi"}
      resizePolicy:
        - resourceName: cpu
          restartPolicy: NotRequired
        - resourceName: memory
          restartPolicy: NotRequired
      securityContext:
        allowPrivilegeEscalation: false
        capabilities: {drop: ["ALL"]}
```

```bash
kubectl apply -f manifests/resizable.yaml
kubectl -n ch06 wait pod resizable --for=condition=Ready --timeout=60s

# CPU を 100m → 300m に
kubectl -n ch06 patch pod resizable --subresource=resize --patch \
  '{"spec":{"containers":[{"name":"c","resources":{"requests":{"cpu":"300m"},"limits":{"cpu":"500m"}}}]}}'

kubectl -n ch06 get pod resizable -o json | jq '.status.containerStatuses[0].resources'
# Pod は再作成されていない (RESTARTS が増えない)
```

### 7. 後片付け

```bash
kubectl delete ns ch06
# worker_count を 2 に戻すなら
# cd ../01-terraform-vpc-ec2/terraform && terraform apply -var 'worker_count=2'
```

## やってみて気づくこと

- 「Node を増やす」は **Terraform で +1 → kubeadm join** の 2 ステップだけ
- drain は **eviction API のラッパ**。PDB が "**運用ガードレール**" として効くのは eviction だけ、というのは知らないと事故る
- Node 障害から Pod の reschedule までは **時間がかかる** (default 5min)。SLO によっては toleration を縮めるべき
- kubelet config は **drop-in でその場、KubeletConfiguration でクラスタ全体** の使い分け
- In-place Resize は v1.33 で beta になり、**HPA / VPA との組み合わせ** の世界が見えてきた

## 参考
- Safely Drain Node: https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/
- PodDisruptionBudget: https://kubernetes.io/docs/concepts/workloads/pods/disruptions/
- Taints and Tolerations: https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/
- KubeletConfiguration: https://kubernetes.io/docs/reference/config-api/kubelet-config.v1beta1/
- In-place Pod Resize: https://kubernetes.io/docs/tasks/configure-pod-container/resize-container-resources/
