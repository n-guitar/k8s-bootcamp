# 04 — Storage: AWS EBS CSI Driver

## ゴール
- **EBS CSI driver** を helm で install (IRSA は無し、Node IAM Role で動かす)
- StorageClass (`gp3`) を定義し、PVC → Pod から dynamic provisioning
- 実際に EBS Volume が作られて attach されることを AWS API で確認
- VolumeSnapshot で **オンラインバックアップ** → snapshot からのリストア

---

## 🤔 なぜ必要？ (ストーリー)

> Track A の Storage 章では `local-path-provisioner` で hostPath を Pod に渡した。
> 本番でそれをやると、**Node 障害 = データロスト**。
>
> 本番の k8s ストレージは **「ブロックストレージを CSI driver 経由で動的にプロビジョニング」** が王道。
> AWS なら EBS、Azure なら Disk、GCP なら PD。
> どれも仕組みは同じ:
> 1. PVC が作られる
> 2. CSI controller が **クラウド API を叩いて Volume を作る**
> 3. CSI node が **kubelet 経由でその Volume を Node に attach + mount**
> 4. Pod がそのディレクトリを見る
>
> "**k8s API ↔ クラウド API の橋渡し**" をするのが CSI driver。中で何が起きているかを **AWS Console で** 観察するのが本章。

## ✨ 面白いポイント (設計)

### 1. **CSI = "**コンテナの世界とストレージの世界を疎結合にする規格**"**

旧 k8s は in-tree (kube-controller-manager のコードに `awsElasticBlockStore` が同梱) だったが、v1.28 以降 **削除**。
今は外部 driver:

```
PVC 作成
  ↓
external-provisioner (sidecar) が CSI controller に CreateVolume RPC
  ↓
controller が AWS API: ec2:CreateVolume
  ↓
Pod が schedule される
  ↓
external-attacher が ControllerPublishVolume → ec2:AttachVolume
  ↓
node-plugin が NodeStageVolume → mkfs + mount
```

> **痺れ所:** "**k8s からクラウド呼び出しのコードを抜く**" ことで、k8s のリリースとストレージ driver のリリースが **独立** になった。
> = AWS が EBS の新機能を出した時、k8s 本体のリリースを待たなくていい。

### 2. **Node IAM Role で動かす最短経路**

本番では **IRSA (IAM Roles for ServiceAccounts) + OIDC provider** が推奨だが、初学者にはやや重い。
本書では Node に EBS 操作の Policy を直接 attach する **最短経路** で動かす (= controller Pod が Node IAM を inherit)。

> **痺れ所:** "**学習用の許容**" と "**本番のベストプラクティス**" の差分が、IAM の世界では IRSA / Pod Identity という **k8s ↔ IAM の橋渡し機構** にある。これは Track C (EKS) でじっくり扱う。

### 3. **VolumeSnapshot = "PVC のスナップショット" を k8s API で扱う**

```
VolumeSnapshot (k8s)  ←→  EBS Snapshot (AWS)
VolumeSnapshotClass   ←→  CSI driver の設定
VolumeSnapshotContent ←→  実際の snapshot 実体
```

PVC と PV の関係をそのまま **時間方向** に拡張したのが Snapshot API。

## 😱 あるある罠

- **EBS は AZ から動かせない**: Pod が別 AZ の Node に schedule されると attach 失敗。**`topology.kubernetes.io/zone`** を見て同じ AZ に Pod を寄せる必要がある (Track B では Subnet 1 つ = 1 AZ なので問題なし)
- **削除しても EBS が残る**: `StorageClass.reclaimPolicy: Retain` のままだと PVC delete でも EBS が残る。学習用は `Delete` で
- **Snapshot は EBS Volume を消しても残る**: 安いが永遠に積み上がる。`99-cleanup` でタグ検索
- **`gp2` をうっかり選ぶ**: gp2 は旧世代で割高。**gp3** が default
- **Node に IAM Policy を attach 忘れ**: controller Pod が `UnauthorizedOperation` でずっと re-schedule

## やること

### 0. 準備

Cilium が入って Node が全て Ready、かつ `kubectl get pods -A` で Pending が無いこと。

```bash
export KUBECONFIG=$PWD/../02-kubeadm-bootstrap/kubeconfig
kubectl get nodes
kubectl get pods -A
```

### 1. EC2 Node に IAM Policy を attach

Track B では Terraform で Node に IAM Role を付けていない (簡略化のため) ので、ここで Instance Profile を作って attach する。

```bash
ROLE_NAME=k8s-bootcamp-node
aws iam create-role --role-name $ROLE_NAME \
  --assume-role-policy-document '{
    "Version":"2012-10-17",
    "Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]
  }' \
  --tags Key=Project,Value=k8s-bootcamp Key=Track,Value=B

aws iam attach-role-policy --role-name $ROLE_NAME \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy

aws iam create-instance-profile --instance-profile-name $ROLE_NAME
aws iam add-role-to-instance-profile \
  --instance-profile-name $ROLE_NAME --role-name $ROLE_NAME

for IID in $(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=k8s-bootcamp" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' --output text); do
  aws ec2 associate-iam-instance-profile \
    --instance-id $IID \
    --iam-instance-profile Name=$ROLE_NAME
done
```

> **本番では IRSA を使う**。Track C (EKS) で扱う。

### 2. snapshot-controller + EBS CSI driver を入れる

```bash
# snapshot CRD と controller (driver と分離している)
kubectl apply -k "https://github.com/kubernetes-csi/external-snapshotter/client/config/crd?ref=v8.0.1"
kubectl apply -k "https://github.com/kubernetes-csi/external-snapshotter/deploy/kubernetes/snapshot-controller?ref=v8.0.1"

# EBS CSI driver
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm repo update

helm upgrade --install aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver \
  --namespace kube-system \
  --version 1.36.0 \
  --set controller.serviceAccount.create=true \
  --set node.serviceAccount.create=true \
  --set enableVolumeSnapshot=true

kubectl -n kube-system rollout status deploy/ebs-csi-controller --timeout=5m
kubectl -n kube-system get pods -l app.kubernetes.io/name=aws-ebs-csi-driver
```

### 3. StorageClass `gp3` を定義

`manifests/storageclass-gp3.yaml`:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
  csi.storage.k8s.io/fstype: ext4
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
allowVolumeExpansion: true
```

```bash
kubectl apply -f manifests/storageclass-gp3.yaml
kubectl get sc
```

### 4. PVC + Pod で実際に使う

`manifests/demo-pvc-pod.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata: {name: ch04}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: data, namespace: ch04}
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: gp3
  resources:
    requests:
      storage: 4Gi
---
apiVersion: v1
kind: Pod
metadata: {name: writer, namespace: ch04}
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 1000
    seccompProfile: {type: RuntimeDefault}
  containers:
    - name: c
      image: busybox:1.36
      command: ["sh", "-c", "while true; do date >> /data/log; sleep 5; done"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities: {drop: ["ALL"]}
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: data
```

```bash
kubectl apply -f manifests/demo-pvc-pod.yaml
kubectl -n ch04 get pvc,pv,pod
```

AWS 側で **本当に EBS が出来ている** ことを確認:

```bash
aws ec2 describe-volumes \
  --filters "Name=tag:kubernetes.io/created-for/pvc/name,Values=data" \
  --query 'Volumes[].{Id:VolumeId,State:State,Size:Size,Type:VolumeType}'
```

→ `gp3` で 4GB の Volume が `in-use` で attach されている。

```bash
kubectl -n ch04 exec writer -- tail -3 /data/log
```

### 5. VolumeSnapshot を試す

`manifests/snapshot-class.yaml`:

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: ebs-snap
driver: ebs.csi.aws.com
deletionPolicy: Delete
```

`manifests/snapshot.yaml`:

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata: {name: data-snap, namespace: ch04}
spec:
  volumeSnapshotClassName: ebs-snap
  source:
    persistentVolumeClaimName: data
```

```bash
kubectl apply -f manifests/snapshot-class.yaml
kubectl apply -f manifests/snapshot.yaml
kubectl -n ch04 get volumesnapshot

aws ec2 describe-snapshots --owner-ids self \
  --filters "Name=tag:CSIVolumeSnapshotName,Values=data-snap" \
  --query 'Snapshots[].{Id:SnapshotId,State:State,Size:VolumeSize}'
```

### 6. Snapshot から restore

`manifests/restore.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: data-restored, namespace: ch04}
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: gp3
  resources:
    requests: {storage: 4Gi}
  dataSource:
    apiGroup: snapshot.storage.k8s.io
    kind: VolumeSnapshot
    name: data-snap
```

```bash
kubectl apply -f manifests/restore.yaml
# 別 Pod を作って /data をマウントすると log が復活している
```

### 7. 後片付け

```bash
kubectl delete ns ch04
# reclaimPolicy=Delete なので PVC 削除で EBS も消える

aws ec2 describe-volumes \
  --filters "Name=tag:Project,Values=k8s-bootcamp" "Name=status,Values=available" \
  --query 'Volumes[].VolumeId'
# 何も残っていないこと

# Snapshot は明示的に消す
aws ec2 describe-snapshots --owner-ids self \
  --filters "Name=tag:Project,Values=k8s-bootcamp" \
  --query 'Snapshots[].SnapshotId' --output text \
  | xargs -n1 -r aws ec2 delete-snapshot --snapshot-id
```

> **AWS 料金注意:** 残った EBS と Snapshot が課金源 No.1。**`available` 状態の Volume があれば即削除**。Snapshot は格安だが **永久に残る** ので明示削除。

## やってみて気づくこと

- 「PVC を apply する → AWS で EBS が出来る」の中継は **CSI driver の sidecar 5 つ** が黙々と回している (provisioner / attacher / resizer / snapshotter / node-driver-registrar)
- k8s API と AWS API は **明確に別世界**。CSI が "領事館" のような役割
- VolumeSnapshot は **k8s 標準** なので、driver を CSI に揃えれば AWS でも GCP でも同じ YAML
- 一方で **AZ の縛り** はクラウド固有で残る。マルチ AZ 設計は CSI でも難所

## 参考
- AWS EBS CSI driver: https://github.com/kubernetes-sigs/aws-ebs-csi-driver
- In-tree → CSI 移行 GA: https://kubernetes.io/blog/2023/04/19/csi-migration-ga-status/
- VolumeSnapshot: https://kubernetes.io/docs/concepts/storage/volume-snapshots/
- IRSA: https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html
