# 06 — Storage (PV / PVC / StorageClass)

## ゴール
- ステートレス vs ステートフルの違い
- **PVC** = "アプリが欲しい論理ストレージ"、**PV** = "実体"、**StorageClass** = "プロビジョナの設計図"
- in-tree volume plugin は **完全消滅**、CSI driver が唯一の選択肢
- AccessMode (RWO / ROX / RWX / RWOP) の使い分け

---

## 🤔 なぜ必要？ (ストーリー)

> あなたは前章までで Web アプリを動かせた。次に PostgreSQL を入れたい。
> Pod の `emptyDir` に DB ファイルを置く?
> → Pod が消えると **データも消える**。これは "**コンテナはステートレス**" の現実。
>
> DB のデータは **Pod のライフサイクルとは独立して** 生き延びてほしい。
> しかも:
> - 開発はローカルディスクで動かしたい
> - 本番は EBS、ステージングは NFS
> - DB は Pod が再スケジュールされてもデータは付いてきてほしい
>
> アプリ作者は「**100 GB の RWO ボリュームが欲しい**」とだけ書きたい。
> 「**それを EBS で出すか NFS で出すか**」はインフラ側の都合。
> この **要求と実体の分離** をやるのが PVC / PV / StorageClass。

## ✨ 面白いポイント (設計)

### 1. **PVC は "**ストレージの宣言型 API**"**

アプリ作者は PVC で「これだけ欲しい」と書く:

```
PVC: 10 GB, accessMode: ReadWriteOnce, storageClassName: gp3
```

すると StorageClass の **プロビジョナ** (= CSI driver) が走り、対応する PV を **動的に作る**。
出来た PV は PVC に bind され、Pod から `volumes:` 経由で参照可能になる。

> **痺れ所:** Pod 側は「PVC `data` を要求」と書くだけ。それが EBS か NFS か Local か、アプリは知らなくていい。
> = **同じ Pod YAML が、開発機 / 本番 / クラウドで動く**。

### 2. **in-tree → CSI への完全移行**

昔は kubelet 自体が AWS EBS や GCE PD のコードを **抱えていた** (in-tree)。
ベンダごとに本体に PR が来るので発展が遅い + クラウドプロバイダごとに更新が縛られる。

→ **CSI** (Container Storage Interface) で **外部プラグイン化**。今は in-tree は完全に削除済み。

> **痺れ所:** これは CNI (ネットワーク) と全く同じ流れ。**コアは抽象だけ、実装はベンダ** という設計思想が、ストレージにも適用された。

### 3. **AccessMode の 4 種**

| Mode | 短縮 | 意味 | 典型 |
|---|---|---|---|
| ReadWriteOnce | RWO | **1 Node** から RW (Pod は複数 OK、同 Node 内) | EBS, ローカル |
| ReadOnlyMany | ROX | 複数 Node から RO | 配布用静的データ |
| ReadWriteMany | RWX | 複数 Node から RW | NFS, EFS, Ceph |
| ReadWriteOncePod | RWOP | **1 Pod** だけ RW (v1.27 GA) | 排他ロック必須の DB |

`ReadWriteOnce` が "Node 単位" なのは、ブロックストレージ (EBS 等) の都合。1 Node の中に複数 Pod を載せて RW させるのは OK。

### 4. **VolumeSnapshot / StatefulSet PVC Retention などの "進化"**

- **VolumeSnapshot** (CSI): PVC をスナップショット → 別 PVC にリストア
- **StatefulSet PVC Retention Policy**: StatefulSet 削除時に PVC を残すかどうか選べる
- **Generic Ephemeral Volume**: Pod inline で PVC 相当を要求 (短命用途)

これらは Track A 07 で深掘り。

## 😱 あるある罠

- **AccessMode を `RWX` で要求したのに `RWO` の SC を使う**: そもそも bind されない → PVC が `Pending` のまま
- **`RWO` のまま 2 Node に Pod を立てたい**: 移動できない。Pod が `ContainerCreating` で固まる
- **PVC を消したら PV も消えた**: `reclaimPolicy: Delete` (デフォルト) の StorageClass を本番 DB で使うのは怖い → `Retain` に変える
- **kind の `local-path-provisioner` は RWX 不可**: 仕方ない、Track B/C で EFS 等を使う
- **`subPath` でホスト書込権限**: PSA `restricted` を有効にした NS では弾かれることがある

## やること

### 0. 準備

```bash
kubectl create ns ch06
kubectl label ns ch06 pod-security.kubernetes.io/enforce=baseline --overwrite
kubectl get storageclass    # ← kind なら "standard" (local-path) が default
```

### 1. PVC を作る (動的プロビジョニング)

```yaml
# pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data
  namespace: ch06
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 1Gi
```

```bash
kubectl apply -f pvc.yaml
kubectl -n ch06 get pvc data
# → STATUS は最初 Pending、SC の volumeBindingMode が "WaitForFirstConsumer" なら Pod が来てから bind
kubectl get pv     # ← 動的に作られた PV を確認
```

### 2. Pod から使う

```yaml
# pod-write.yaml
apiVersion: v1
kind: Pod
metadata:
  name: writer
  namespace: ch06
spec:
  restartPolicy: Never
  containers:
    - name: w
      image: busybox:1.36
      command: ["sh", "-c", "date >> /data/log && cat /data/log && sleep 5"]
      volumeMounts: [{name: vol, mountPath: /data}]
  volumes:
    - name: vol
      persistentVolumeClaim: {claimName: data}
```

```bash
kubectl apply -f pod-write.yaml
kubectl -n ch06 logs writer
```

### 3. Pod を消しても **データは残る** ことを確認

```bash
kubectl -n ch06 delete pod writer
kubectl apply -f pod-write.yaml   # 同じ PVC を再 mount
kubectl -n ch06 logs writer       # ← 前回の date 行も残っている
```

→ "**コンテナはステートレス、ボリュームはステートフル**" を体感。

### 4. StorageClass を覗く

```bash
kubectl get sc standard -o yaml | head -30
```

注目点:
- `provisioner: rancher.io/local-path` ← これが CSI 相当の plug-in
- `reclaimPolicy: Delete` ← PVC 削除と一緒に PV も消える設定
- `volumeBindingMode: WaitForFirstConsumer` ← Pod が来てから bind

### 5. AccessMode を変えて挙動を見る

`accessModes: ["ReadWriteMany"]` に変えて apply してみる:

```bash
# kind の local-path は RWX 非対応なので PVC が Pending のまま
kubectl -n ch06 describe pvc data | grep -A3 Events
# → "no volume plugin matched" 系のメッセージ
```

→ Track B/C で EFS を使う動機が明確に。

### 6. 後片付け

```bash
kubectl delete ns ch06
kubectl get pv    # ← reclaimPolicy: Delete なので PV も消える
```

## やってみて気づくこと

- **PVC = アプリの欲しい量**、**PV = 実体**、**SC = 出し方** の三段
- "**動的プロビジョニング**" のおかげで PV を手で作る場面は本番でもまずない
- アプリ YAML には `volumes: persistentVolumeClaim: { claimName: data }` としか書かない
- → **同じアプリ YAML が、kind / EBS / EFS で動く** という移植性

## 参考

- Storage: https://kubernetes.io/docs/concepts/storage/
- CSI: https://kubernetes-csi.github.io/docs/
- In-tree → CSI: https://kubernetes.io/blog/2023/04/19/csi-migration-ga-status/
- RWOP: https://kubernetes.io/blog/2023/04/20/read-write-once-pod-access-mode-beta/
