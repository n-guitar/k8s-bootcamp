# 03 — Sidecar Containers (KEP-753)

## ゴール
v1.33 で stable になった **ネイティブ Sidecar Containers** (`initContainers[].restartPolicy: Always`) を体験する。

## やること (予定)
1. 旧来パターン: `containers` に sidecar を並べる → Job が永遠に終わらない問題を再現
2. 新パターン: `initContainers` に `restartPolicy: Always` の sidecar
3. メインコンテナが exit したら sidecar も終了することを観察 (Job 完走)
4. 起動順序が "sidecar → main" になることを確認

## TODO
- [ ] `manifests/job-old-pattern.yaml`
- [ ] `manifests/job-native-sidecar.yaml`
- [ ] ログ取り sidecar の例

## 参考
- KEP-753: https://github.com/kubernetes/enhancements/tree/master/keps/sig-node/753-sidecar-containers
- Blog: https://kubernetes.io/blog/2023/08/25/native-sidecar-containers/
