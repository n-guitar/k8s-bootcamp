# 05 — CSI: EBS + EFS

## ゴール
- EBS CSI driver (managed addon) で **ReadWriteOnce** PV
- EFS CSI driver で **ReadWriteMany** PV
- VolumeSnapshot / StatefulSet retention policy も触る

## やること (予定)
1. EBS CSI は addon で済ませ、`StorageClass` (gp3) を default に
2. EFS をプロビジョン (Terraform で FileSystem + MountTarget)
3. EFS CSI driver を helm install
4. `StatefulSet` + `volumeClaimTemplates` で挙動確認
5. StatefulSet PVC Retention Policy で「delete 時に PVC を残す/消す」を切り替え

## TODO
- [ ] `terraform/efs.tf`
- [ ] EFS Access Point の利用例
- [ ] snapshot-controller の install (EBS の VolumeSnapshot 用)

## 参考
- EBS CSI: https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html
- EFS CSI: https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html
- PVC retention: https://kubernetes.io/blog/2023/02/13/sts-pvc-retention-policy/
