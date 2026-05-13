# 04 — Storage: AWS EBS CSI Driver

## ゴール
in-tree `awsElasticBlockStore` は v1.28 以降使えない。**EBS CSI driver** を IRSA 無し (Node IAM Role) で動かして、動的プロビジョニングを体験する。

## やること (予定)
1. worker Node に EBS 操作の IAM Policy を attach
2. EBS CSI driver を helm install
3. `StorageClass` (gp3) を定義
4. PVC → Pod で実際にマウント
5. `VolumeSnapshot` を試す (snapshot-controller も install)

## TODO
- [ ] `manifests/storageclass-gp3.yaml`
- [ ] EBS CSI 用 IAM Policy JSON
- [ ] snapshot 戻し例

## 参考
- AWS EBS CSI: https://github.com/kubernetes-sigs/aws-ebs-csi-driver
- In-tree → CSI 移行: https://kubernetes.io/blog/2023/04/19/csi-migration-ga-status/
