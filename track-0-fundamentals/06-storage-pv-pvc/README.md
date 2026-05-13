# 06 — Storage (PV / PVC / StorageClass)

## ゴール
- ステートレスとステートフルの違い
- **PVC** が「アプリが要求する論理ストレージ」、**PV** が「実体」、**StorageClass** が「プロビジョナの設計」
- kind 同梱の `local-path-provisioner` で動的プロビジョニング体験
- in-tree volume plugin が完全消滅して **CSI driver 一択** であることを明示

## やること (予定)
1. デフォルトの `local-path` StorageClass を確認
2. PVC + Pod でファイルを書き込み、Pod を消して PVC を再マウント → 残ることを確認
3. accessModes (RWO / ROX / RWX / RWOP) の違いを表で説明
4. `kubectl get csinode, csidriver` で CSI を確認
5. (発展) VolumeSnapshot は Track A 07 で深掘りする旨案内

## TODO
- [ ] `manifests/pvc.yaml`, `pod-with-pvc.yaml`
- [ ] accessModes 早見表
- [ ] EBS / EFS / NFS への伏線 (Track B/C)

## 参考
- Storage: https://kubernetes.io/docs/concepts/storage/
- CSI: https://kubernetes-csi.github.io/docs/
