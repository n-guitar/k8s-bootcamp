# 07 — Storage / CSI

## ゴール
- in-tree volume plugin が消え、**CSI driver 経由** が唯一の選択肢になった現状を体感
- kind 同梱の **`local-path-provisioner`** で動的 PVC を作る
- **VolumeSnapshot** で PVC をスナップ → 別 PVC にリストア
- **Generic Ephemeral Volume** を Pod inline で利用
- **StatefulSet PVC retention policy** (v1.27 GA) でクラスタ縮退時の挙動を制御
- **ReadWriteOncePod (RWOP)** で本当に排他になることを確認 (v1.29 GA)

---

## 🤔 なぜ必要？ (ストーリー)

> 4 年前のあなた:「`gcePersistentDisk` を Pod に直接書けば EBS みたいに使えてた」
> 今日のあなた:「`gcePersistentDisk` を書いた YAML を apply したら **The PersistentVolume "..." is invalid: spec.gcePersistentDisk: Forbidden** と出る…」
>
> 何が起きた? — **in-tree CSI Migration** が完了し、v1.25 以降は in-tree volume plugin の **コードが消えた**。今は GKE PD も EBS も Azure Disk も、**全部 CSI driver 経由**。
>
> 別の日、上司:「Postgres の PVC のスナップショットを取って QA 環境に渡したい」
> → 4 年前は外部スクリプトで `aws ec2 create-snapshot` を呼んでいた。
> → 今は **`VolumeSnapshot` CRD** で `kubectl apply` だけ。Velero も内部でこれを使う。
>
> さらに別の日:「StatefulSet を replicas 5→0 にしたら PVC が残ってディスク代が無駄」
> → 4 年前は手動 `kubectl delete pvc`。**v1.27 で `persistentVolumeClaimRetentionPolicy`** が GA。

これらが「ストレージまわりで離れていた間に起きた事件」のサマリです。

```
in-tree plugin  : kubelet の中に AWS/GCE のコードが入っていた (= k8s release と同期)
        ↓
CSI driver      : 別 Pod (DaemonSet+Deployment) として動く。リリースサイクル独立
```

## ✨ 面白いポイント (設計)

### 1. **CSI = "ストレージベンダから k8s を切り離す境界線"**

kubelet ↔ CSI socket ↔ ベンダ製コンテナ、という構造。**kubelet にベンダ固有コードがない**。

```
kubelet ──gRPC── csi.sock ──── csi-driver Pod ── 実ストレージ (EBS/Ceph/...)
```

> **痺れ所:** k8s v1.X のリリースを待たずにベンダがドライバを更新できる。`kubectl get csidrivers` で「今このクラスタにどんなストレージ実装があるか」が一覧できる。

### 2. **VolumeSnapshot の 3 CRD**

```
VolumeSnapshotClass    : 「どう撮るか」(= CSI driver + パラメタ)
VolumeSnapshot         : 「これを撮って」(= 利用者が書く)
VolumeSnapshotContent  : 「撮った実体」(= controller が作る)
```

PV / PVC / StorageClass と同じ三角形。**設計の一貫性**。

### 3. **Generic Ephemeral Volume = "Pod の寿命 + 動的プロビジョニング"**

emptyDir は容量/ StorageClass を指定できない、PVC は手動で作る必要がある。**間が無かった**。
Generic Ephemeral は Pod spec に **inline で PVC テンプレ** を書ける:

```yaml
volumes:
  - name: scratch
    ephemeral:
      volumeClaimTemplate:
        spec:
          storageClassName: standard
          resources: {requests: {storage: 1Gi}}
```

Pod が消えたら PVC も GC される。**バッチ用途で神**。

### 4. **ReadWriteOncePod (RWOP) — "本当の排他"**

`ReadWriteOnce` は「**1 ノードから R/W**」だった → ノードが同じなら **複数 Pod から書ける**。これで壊れたデータベースの話は多い。
`ReadWriteOncePod` (v1.29 GA) は「**1 Pod から R/W**」。物理的に守られる。

### 5. **StatefulSet PVC retention policy (v1.27 GA)**

```yaml
spec:
  persistentVolumeClaimRetentionPolicy:
    whenDeleted: Delete  # StatefulSet が消えたら PVC も消す
    whenScaled:  Delete  # scale-in した時は PVC を消す
```

「ディスクが残ってクラウド代が膨らむ」あるあるが、宣言的に解決。

## 😱 あるある罠

- **`gcePersistentDisk` / `awsElasticBlockStore` を直書きしたマニフェストが残っている**: v1.25 以降は apiserver が拒否する。CSI driver の `StorageClass` 経由に書き換え必須
- **kind の `local-path` で `VolumeSnapshot`**: `local-path-provisioner` は **snapshot 非対応**。snapshot を試すには **`csi-driver-host-path`** を入れる (この章でやる)
- **external-snapshotter CRD を入れ忘れる**: `VolumeSnapshot` apply で `no matches for kind` エラー
- **`reclaimPolicy: Delete` の StorageClass で本番**: PVC を消したら PV (= 実ディスク) も消える。本番は `Retain` が安全寄り
- **RWO と RWOP の混同**: 古いブログで「RWO で排他」と書いてあるが、それは嘘。**RWOP でないと排他にならない**
- **kind の容量**: ホスト Docker volume を共有しているので、ホスト残量を超えた瞬間に **全 PVC が同時に死ぬ**。Track B/C への伏線

## やること

### 0. 準備 — kind 同梱の `local-path` を確認

```bash
kubectl get sc
# NAME                 PROVISIONER             RECLAIMPOLICY   ...
# standard (default)   rancher.io/local-path   Delete

kubectl get csidrivers
# kind 標準では local-path-provisioner は in-cluster controller で、CSI driver としては登録されていない
# (= "CSI 化されていない旧スタイル" のレアな実例)

kubectl create ns ch07-csi
kubectl label ns ch07-csi pod-security.kubernetes.io/enforce=baseline --overwrite
```

### 1. 動的 PVC を作って、Pod から書き込む

```yaml
# pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: data, namespace: ch07-csi}
spec:
  accessModes: [ReadWriteOnce]
  resources: {requests: {storage: 256Mi}}
  storageClassName: standard
---
apiVersion: v1
kind: Pod
metadata: {name: writer, namespace: ch07-csi}
spec:
  containers:
    - name: w
      image: busybox:1.36
      command: ["sh", "-c", "echo hello-from-writer > /data/msg && sleep 3600"]
      volumeMounts:
        - {name: data, mountPath: /data}
  volumes:
    - name: data
      persistentVolumeClaim: {claimName: data}
```

```bash
kubectl apply -f pvc.yaml
kubectl -n ch07-csi wait --for=condition=Ready pod/writer --timeout=60s
kubectl -n ch07-csi exec writer -- cat /data/msg
# → hello-from-writer
```

### 2. CSI driver (`csi-driver-host-path`) と external-snapshotter を入れる

`local-path` は snapshot 非対応のため、snapshot 検証用の **hostpath CSI** を追加。kind 1 ノード前提のデモ用 driver なので **本番では使わない**。

```bash
# 2-a. CRD (VolumeSnapshot* 3 種)
SNAP_VER=v8.0.1
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${SNAP_VER}/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${SNAP_VER}/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${SNAP_VER}/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml

# 2-b. snapshot-controller (kube-system)
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${SNAP_VER}/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${SNAP_VER}/deploy/kubernetes/snapshot-controller/setup-snapshot-controller.yaml

# 2-c. hostpath CSI driver
git clone --depth=1 https://github.com/kubernetes-csi/csi-driver-host-path /tmp/csi-hostpath
cd /tmp/csi-hostpath
./deploy/kubernetes-latest/deploy.sh
kubectl apply -f ./examples/csi-storageclass.yaml      # name: csi-hostpath-sc
kubectl apply -f ./examples/csi-snapshotclass.yaml     # name: csi-hostpath-snapclass
cd -

kubectl get csidrivers
# hostpath.csi.k8s.io     true ...
kubectl get volumesnapshotclass
```

### 3. snapshot を撮って別 PVC に復元

```yaml
# pvc-csi.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: src, namespace: ch07-csi}
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: csi-hostpath-sc
  resources: {requests: {storage: 256Mi}}
---
apiVersion: v1
kind: Pod
metadata: {name: filler, namespace: ch07-csi}
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: ["sh","-c","echo snap-source-data > /d/msg && sleep 3600"]
      volumeMounts: [{name: v, mountPath: /d}]
  volumes:
    - {name: v, persistentVolumeClaim: {claimName: src}}
```

```bash
kubectl apply -f pvc-csi.yaml
kubectl -n ch07-csi wait --for=condition=Ready pod/filler --timeout=60s
```

```yaml
# snapshot.yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata: {name: src-snap-1, namespace: ch07-csi}
spec:
  volumeSnapshotClassName: csi-hostpath-snapclass
  source:
    persistentVolumeClaimName: src
```

```bash
kubectl apply -f snapshot.yaml
kubectl -n ch07-csi get volumesnapshot src-snap-1
# READYTOUSE: true になるまで待つ
kubectl -n ch07-csi wait --for=jsonpath='{.status.readyToUse}'=true volumesnapshot/src-snap-1 --timeout=60s
```

```yaml
# pvc-restore.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: restored, namespace: ch07-csi}
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: csi-hostpath-sc
  resources: {requests: {storage: 256Mi}}
  dataSource:
    apiGroup: snapshot.storage.k8s.io
    kind: VolumeSnapshot
    name: src-snap-1
---
apiVersion: v1
kind: Pod
metadata: {name: reader, namespace: ch07-csi}
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: ["sh","-c","cat /d/msg && sleep 3600"]
      volumeMounts: [{name: v, mountPath: /d}]
  volumes:
    - {name: v, persistentVolumeClaim: {claimName: restored}}
```

```bash
kubectl apply -f pvc-restore.yaml
kubectl -n ch07-csi wait --for=condition=Ready pod/reader --timeout=60s
kubectl -n ch07-csi logs reader
# → snap-source-data   (= snapshot から復元されている)
```

> **痺れ所:** `dataSource` の 3 行で **クラウドベンダ問わず** snapshot リストアが書けるようになった。EBS / GCE PD / Ceph いずれでも同じ YAML。

### 4. Generic Ephemeral Volume

```yaml
# ephemeral.yaml
apiVersion: v1
kind: Pod
metadata: {name: ephemeral-demo, namespace: ch07-csi}
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: ["sh","-c","df -h /scratch && echo done > /scratch/x && sleep 30"]
      volumeMounts: [{name: scratch, mountPath: /scratch}]
  volumes:
    - name: scratch
      ephemeral:
        volumeClaimTemplate:
          metadata: {labels: {workload: batch}}
          spec:
            accessModes: [ReadWriteOnce]
            storageClassName: csi-hostpath-sc
            resources: {requests: {storage: 64Mi}}
```

```bash
kubectl apply -f ephemeral.yaml
kubectl -n ch07-csi get pvc -l workload=batch     # ← 自動で PVC が作られている
kubectl -n ch07-csi wait --for=condition=Ready pod/ephemeral-demo --timeout=60s
kubectl -n ch07-csi logs ephemeral-demo

# Pod を消すと PVC も自動で消える
kubectl -n ch07-csi delete pod ephemeral-demo
kubectl -n ch07-csi get pvc -l workload=batch     # ← 無い
```

### 5. ReadWriteOncePod (RWOP)

RWO と異なり、**同じノード上でも 2 つ目の Pod から mount できない**:

```yaml
# rwop.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: solo, namespace: ch07-csi}
spec:
  accessModes: [ReadWriteOncePod]
  storageClassName: csi-hostpath-sc
  resources: {requests: {storage: 64Mi}}
---
apiVersion: v1
kind: Pod
metadata: {name: holder, namespace: ch07-csi}
spec:
  containers:
    - {name: c, image: busybox:1.36, command: ["sleep","3600"], volumeMounts: [{name: v, mountPath: /d}]}
  volumes: [{name: v, persistentVolumeClaim: {claimName: solo}}]
---
apiVersion: v1
kind: Pod
metadata: {name: intruder, namespace: ch07-csi}
spec:
  containers:
    - {name: c, image: busybox:1.36, command: ["sleep","3600"], volumeMounts: [{name: v, mountPath: /d}]}
  volumes: [{name: v, persistentVolumeClaim: {claimName: solo}}]
```

```bash
kubectl apply -f rwop.yaml
kubectl -n ch07-csi wait --for=condition=Ready pod/holder --timeout=60s
kubectl -n ch07-csi get pod intruder
# → Pending、describe すると "volume is already used by pod ... and access mode is ReadWriteOncePod"
kubectl -n ch07-csi describe pod intruder | tail -5
```

### 6. StatefulSet PVC retention policy

```yaml
# sts.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata: {name: db, namespace: ch07-csi}
spec:
  serviceName: db
  replicas: 3
  selector: {matchLabels: {app: db}}
  persistentVolumeClaimRetentionPolicy:
    whenDeleted: Delete
    whenScaled:  Delete
  template:
    metadata: {labels: {app: db}}
    spec:
      containers:
        - name: c
          image: busybox:1.36
          command: ["sh","-c","sleep 3600"]
          volumeMounts: [{name: data, mountPath: /data}]
  volumeClaimTemplates:
    - metadata: {name: data}
      spec:
        accessModes: [ReadWriteOnce]
        storageClassName: csi-hostpath-sc
        resources: {requests: {storage: 64Mi}}
---
apiVersion: v1
kind: Service
metadata: {name: db, namespace: ch07-csi}
spec:
  clusterIP: None
  selector: {app: db}
  ports: [{port: 80}]
```

```bash
kubectl apply -f sts.yaml
kubectl -n ch07-csi rollout status sts/db --timeout=120s
kubectl -n ch07-csi get pvc -l app=db
# data-db-0, data-db-1, data-db-2

# scale-in: PVC も消える
kubectl -n ch07-csi scale sts/db --replicas=1
kubectl -n ch07-csi get pvc -l app=db
# → data-db-0 だけ残る (whenScaled: Delete)
```

> `whenScaled: Retain` ならディスク残置、`Delete` なら同時 GC。**意図を YAML に書ける**。

### 7. 後片付け

```bash
kubectl delete ns ch07-csi
# hostpath CSI driver は他章では不要、消したければ:
# kubectl delete -f /tmp/csi-hostpath/deploy/kubernetes-latest/  --ignore-not-found
```

## やってみて気づくこと

- `kubectl get csidrivers` で **そのクラスタが何で永続化しているか** が一覧できる。in-tree 時代には無かった
- VolumeSnapshot は **3 つの CRD** で構成され、PV/PVC/StorageClass と同じ三角形になっている設計の美しさ
- Generic Ephemeral は **emptyDir と PVC の間の穴** を埋める存在
- RWOP は本当に **同一ノード同一 Pod 以外** から mount できず、データ破壊の温床が 1 つ消えた
- StatefulSet retention policy で「scale-in したらディスクも返す」が **宣言的** に書ける
- **kind の `local-path` だけでは snapshot ができない** という制約を体感 → Track B/C で本物の CSI (EBS / EFS) を触る伏線

## 参考

- CSI: https://kubernetes-csi.github.io/docs/
- in-tree → CSI migration: https://kubernetes.io/blog/2024/02/26/volume-migration-ga/
- VolumeSnapshot: https://kubernetes.io/docs/concepts/storage/volume-snapshots/
- Generic Ephemeral Volume: https://kubernetes.io/docs/concepts/storage/ephemeral-volumes/#generic-ephemeral-volumes
- ReadWriteOncePod: https://kubernetes.io/blog/2023/04/20/read-write-once-pod-access-mode-beta/
- StatefulSet PVC retention: https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/#persistentvolumeclaim-retention
- csi-driver-host-path: https://github.com/kubernetes-csi/csi-driver-host-path
