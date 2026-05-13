# 07 — Scheduling

## ゴール
- scheduler は何を見て Pod を Node に配置するか
- `nodeSelector` / **Taint と Toleration** / **Affinity** / **topologySpreadConstraints** の使い分け
- `resources.requests/limits` がスケジューリングと QoS にどう効くか

## やること (予定)
1. ノードにラベル付け → `nodeSelector` で配置を固定
2. ノードに taint → toleration なし Pod が乗らないことを確認
3. Pod Affinity / Anti-Affinity で「同じ Node に乗せたい/避けたい」
4. `topologySpreadConstraints` でゾーン分散 (kind の zone ラベル疑似)
5. requests/limits を変えて QoS class (`Guaranteed` / `Burstable` / `BestEffort`) を観察

## TODO
- [ ] `manifests/` の各サンプル
- [ ] In-place Pod Resize は Track A/B で扱う旨アナウンス
- [ ] 旧 chapter5 との対応

## 参考
- Scheduling: https://kubernetes.io/docs/concepts/scheduling-eviction/
- Topology Spread: https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/
