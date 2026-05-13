# 07 — Storage / CSI

## ゴール
in-tree volume plugin が消えた現状、**CSI driver 経由** が唯一の選択肢であることを体感する。kind 同梱の `local-path-provisioner` を使い、**VolumeSnapshot** / **ReadWriteOncePod** / **Generic Ephemeral Volume** に触れる。

## やること (予定)
1. デフォルトの `local-path` StorageClass で PVC を作る
2. **VolumeSnapshot** で取得 → 別 PVC にリストア
3. **ReadWriteOncePod** アクセスモードで排他確認
4. **Generic Ephemeral Volume** を Pod inline で利用
5. `kubectl get csinode/csidriver` で CSI 配線を確認

## TODO
- [ ] `manifests/pvc.yaml`, `volumesnapshot.yaml`, `pvc-restore.yaml`
- [ ] external-snapshotter のインストール手順
- [ ] StatefulSet PVC retention policy の例

## 参考
- VolumeSnapshot: https://kubernetes.io/docs/concepts/storage/volume-snapshots/
- ReadWriteOncePod: https://kubernetes.io/blog/2023/04/20/read-write-once-pod-access-mode-beta/
