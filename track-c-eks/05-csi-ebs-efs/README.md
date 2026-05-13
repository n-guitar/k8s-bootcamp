# 05 — CSI: EBS (RWO) + EFS (RWX)

## ゴール
- **EBS CSI driver** (managed addon) を default StorageClass に。**gp3** で IOPS / throughput を分離課金
- **EFS CSI driver** を helm で導入し、**ReadWriteMany** PV を体感
- **EFS Access Point** で namespace / 用途ごとにディレクトリ + UID/GID を分離
- StatefulSet `volumeClaimTemplates` と **PVC Retention Policy** で「delete 時に残す/消す」を切替
- (発展) `VolumeSnapshot` で EBS スナップショット → 復元

---

## 🤔 なぜ必要？ (ストーリー)

> Track 0 / B では `local-path` provisioner を使った。1 Node に張り付き、Node を消すとデータが消える PV。
>
> 本番では:
> - DB は 1 Pod = 1 Volume の **RWO** が欲しい (= EBS)
> - 静的ファイルや legacy アプリは複数 Pod から共有したい **RWX** が要る (= EFS)
> - スナップショットを Velero / VolumeSnapshot 経由で日次取りたい (= EBS Snapshot)
>
> 「**面倒な所はクラウドに任せ、面白い所だけ自分で書く**」の最たる場所がストレージ。
> Replication / Snapshot / Encryption / IAM を AWS に丸投げし、**マニフェストには `accessModes` と `storage` だけ書く**。

## ✨ 面白いポイント (設計)

### 1. **EBS gp3 で IOPS / Throughput を「容量と分離」課金**
> **痺れ所:** gp2 は容量に応じて IOPS が決まる罠 (100GB なら 300 IOPS)。gp3 は **3000 IOPS / 125 MB-s が無料枠**、超過分だけ課金。
> StorageClass に `type: gp3` + `iops: 3000` を書くだけ。

### 2. **EFS Access Point = NFS の "view" を YAML で**
> **痺れ所:** Access Point ごとに **rootDirectory + UID/GID** が刺さる。アプリは「自分の Access Point」をマウントするだけで、他人の領域を見れない。
> 1 FileSystem = N アプリの multi-tenancy が綺麗。

### 3. **StatefulSet PVC Retention Policy (v1.27 GA)**
> **痺れ所:** `whenScaled` / `whenDeleted` で「StatefulSet を scale down / delete した時 PVC を残すか」を **宣言**。
> 「DB を一旦消したらデータも全部飛んだ」事故が **ポリシーで防げる**。

### 4. **Pod Identity で CSI driver の IAM**
EFS / EBS CSI driver 自体が EFS や EC2 API を叩くので、その権限は **Pod Identity Association** で渡す。

> **コスト注意:** EBS gp3 は $0.096/GB-月、EFS は $0.36/GB-月 (4 倍弱)。**RWX 必須な所だけ EFS**、それ以外は EBS。

## 😱 あるある罠

- **default StorageClass が `gp2` のまま** → 既存 PVC が新 gp3 にならない。`storageclass.kubernetes.io/is-default-class: "true"` を gp3 にだけ付ける
- **EFS MountTarget を Node の **全 AZ** に作っていない** → 別 AZ の Node から mount できず Pod が CrashLoop
- **EFS Security Group の 2049/tcp** を EKS Node SG から許可していない → タイムアウトで mount できない
- **StatefulSet PVC は **default では消えない**** → 知らないと「StS 消したのに EBS だけ毎月課金」
- **CSI driver の version を **k8s minor に揃え忘れ**** → SnapshotClass / VolumeAttributesClass の API 差で動かない
- **VolumeSnapshot を取って削除しない** → AWS 側に snapshot がずっと残る (= 課金)

## やること

### 0. 準備

01 章で EBS CSI driver の addon が入っている。
Pod Identity Agent も動いている。

```bash
kubectl get csidriver
# ebs.csi.aws.com が居る
```

### 1. gp3 StorageClass を default に

[`manifests/storageclass-gp3.yaml`](./manifests/storageclass-gp3.yaml):

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
  iops: "3000"
  throughput: "125"
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
allowVolumeExpansion: true
```

```bash
# 既存の gp2 から default を剥がす
kubectl annotate sc gp2 storageclass.kubernetes.io/is-default-class- || true
kubectl apply -f manifests/storageclass-gp3.yaml
kubectl get sc
```

### 2. EBS で StatefulSet (PostgreSQL を 1 Pod)

```yaml
# manifests/postgres-sts.yaml
apiVersion: v1
kind: Service
metadata: { name: pg, namespace: default }
spec:
  clusterIP: None
  selector: { app: pg }
  ports: [{ port: 5432 }]
---
apiVersion: apps/v1
kind: StatefulSet
metadata: { name: pg, namespace: default }
spec:
  serviceName: pg
  replicas: 1
  selector: { matchLabels: { app: pg } }
  template:
    metadata: { labels: { app: pg } }
    spec:
      containers:
        - name: postgres
          image: postgres:16-alpine
          env:
            - { name: POSTGRES_PASSWORD, value: "change-me" }
            - { name: PGDATA,            value: "/var/lib/postgresql/data/pgdata" }
          volumeMounts:
            - { name: data, mountPath: /var/lib/postgresql/data }
  volumeClaimTemplates:
    - metadata: { name: data }
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: gp3
        resources: { requests: { storage: 5Gi } }
  # ★ v1.27+ GA: scale-down / delete 時に PVC を保護
  persistentVolumeClaimRetentionPolicy:
    whenScaled: Retain
    whenDeleted: Retain
```

```bash
kubectl apply -f manifests/postgres-sts.yaml
kubectl get pvc,pv -w        # EBS volume が WaitForFirstConsumer → Bound に
```

### 3. EFS を Terraform で作る

```hcl
# terraform/efs.tf
resource "aws_security_group" "efs" {
  name   = "bootcamp-efs"
  vpc_id = module.vpc.vpc_id
  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [module.eks.cluster_primary_security_group_id]
  }
  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_efs_file_system" "shared" {
  encrypted          = true
  performance_mode   = "generalPurpose"
  throughput_mode    = "elastic"
}

resource "aws_efs_mount_target" "shared" {
  for_each        = toset(module.vpc.private_subnets)
  file_system_id  = aws_efs_file_system.shared.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_access_point" "app" {
  file_system_id = aws_efs_file_system.shared.id
  posix_user { uid = 1000  gid = 1000 }
  root_directory {
    path = "/app"
    creation_info { owner_uid = 1000  owner_gid = 1000  permissions = "0755" }
  }
}

output "efs_id"                { value = aws_efs_file_system.shared.id }
output "efs_access_point_app"  { value = aws_efs_access_point.app.id }
```

```bash
cd terraform && terraform apply
```

### 4. EFS CSI driver を helm install + Pod Identity

```hcl
# terraform/efs-csi.tf
module "efs_csi_pi" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4"

  name                       = "efs-csi-driver"
  attach_aws_efs_csi_policy  = true

  associations = {
    main = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "efs-csi-controller-sa"
    }
  }
}
```

```bash
helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/
helm upgrade --install aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver \
  --namespace kube-system \
  --set controller.serviceAccount.create=true \
  --set controller.serviceAccount.name=efs-csi-controller-sa \
  --wait
```

### 5. EFS StorageClass + PVC

```yaml
# manifests/storageclass-efs.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata: { name: efs-sc }
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
  fileSystemId: fs-xxxxxxxx        # ← terraform output efs_id
  directoryPerms: "0755"
  gidRangeStart: "1000"
  gidRangeEnd: "2000"
  basePath: "/dynamic_provisioning"
reclaimPolicy: Delete
volumeBindingMode: Immediate
```

```yaml
# manifests/efs-demo.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: shared, namespace: default }
spec:
  accessModes: ["ReadWriteMany"]
  storageClassName: efs-sc
  resources: { requests: { storage: 5Gi } }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: writer, namespace: default }
spec:
  replicas: 3            # ★ 3 Pod が同じ PV を書きに来る
  selector: { matchLabels: { app: writer } }
  template:
    metadata: { labels: { app: writer } }
    spec:
      containers:
        - name: w
          image: alpine:3.20
          command: ["sh", "-c"]
          args:
            - 'while true; do echo "$(hostname) $(date)" >> /mnt/log.txt; sleep 5; done'
          volumeMounts:
            - { name: shared, mountPath: /mnt }
      volumes:
        - name: shared
          persistentVolumeClaim: { claimName: shared }
```

```bash
kubectl apply -f manifests/storageclass-efs.yaml
kubectl apply -f manifests/efs-demo.yaml
kubectl exec deploy/writer -- tail -n 20 /mnt/log.txt
# → 3 つの hostname が同じファイルに書き込まれている (= RWX)
```

### 6. (発展) VolumeSnapshot で EBS スナップショット

```bash
# CRD と snapshot-controller を入れる (kustomize)
kubectl apply -k "https://github.com/kubernetes-csi/external-snapshotter/client/config/crd?ref=v8.0.1"
kubectl apply -k "https://github.com/kubernetes-csi/external-snapshotter/deploy/kubernetes/snapshot-controller?ref=v8.0.1"
```

```yaml
# manifests/snapshot.yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata: { name: ebs-snap }
driver: ebs.csi.aws.com
deletionPolicy: Delete
---
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata: { name: pg-snap-1, namespace: default }
spec:
  volumeSnapshotClassName: ebs-snap
  source:
    persistentVolumeClaimName: data-pg-0
```

```bash
kubectl apply -f manifests/snapshot.yaml
kubectl get volumesnapshot      # readyToUse: true になるのを待つ
aws ec2 describe-snapshots --owner-ids self --filters Name=tag:Project,Values=k8s-bootcamp
```

### 7. 後片付け (**EBS / EFS の課金停止が肝**)

```bash
kubectl delete -f manifests/efs-demo.yaml
kubectl delete -f manifests/storageclass-efs.yaml
kubectl delete -f manifests/snapshot.yaml || true
kubectl delete statefulset pg
# ★ Retain にしているので PVC は残る。本気で消すなら:
kubectl delete pvc -l app=pg
# EFS と Snapshot は terraform destroy / aws cli で
```

> **重要:** `kubectl delete pvc` で **EBS volume も** 物理削除される (reclaim=Delete のため)。残しておきたいなら先に `kubectl edit pvc` で finalizer を外して reclaim=Retain。

## やってみて気づくこと

- EBS は **AZ 固定**。Pod が別 AZ に re-schedule されると mount できない (= StS で同じ AZ に張り付く設計)
- EFS は **AZ をまたぐ**。MountTarget を全 AZ に置けば Pod がどこへ行っても OK
- gp3 の IOPS / throughput が **storage 容量から独立** している魔法
- StatefulSet を delete しても **PVC が retain で残る** ことを目視すると、設計の重みが分かる
- Snapshot は **2 秒で取れる** が、復元 (PVC 作成) は分単位

## 参考

- EBS CSI driver: https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html
- EFS CSI driver: https://github.com/kubernetes-sigs/aws-efs-csi-driver
- gp3 の特徴: https://aws.amazon.com/ebs/general-purpose/
- PVC Retention Policy: https://kubernetes.io/blog/2023/02/13/sts-pvc-retention-policy/
- VolumeSnapshot: https://kubernetes.io/docs/concepts/storage/volume-snapshots/
