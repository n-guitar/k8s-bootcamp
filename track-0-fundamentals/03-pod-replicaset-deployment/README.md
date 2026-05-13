# 03 — Pod / ReplicaSet / Deployment

## ゴール
- 最小単位 **Pod** を理解 (1 Pod = 1 ネットワーク名前空間 / 複数コンテナ可)
- 自己修復させたい → **ReplicaSet**
- ローリング更新 / ロールバックしたい → **Deployment**

## やること (予定)
1. nginx を Pod 単体で `kubectl apply`
2. `kubectl delete pod` で消える → 復活しないことを確認
3. ReplicaSet で同じ Pod を 3 つ動かす、1 つ消して復活を観察
4. Deployment にして image tag を変えて `kubectl rollout status`
5. `kubectl rollout undo` でロールバック

## TODO
- [ ] `manifests/pod.yaml`, `replicaset.yaml`, `deployment.yaml`
- [ ] 旧 chapter3 の対応関係メモ
- [ ] `kubectl rollout` のサブコマンド一覧

## 参考
- Workloads: https://kubernetes.io/docs/concepts/workloads/
