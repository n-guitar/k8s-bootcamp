# 02 — kubectl とクラスタ

## ゴール
- kind で control-plane×1 / worker×2 のクラスタを立てる
- `kubectl` の超基本 (`get`, `describe`, `logs`, `exec`, `apply`, `delete`)
- core component (kube-apiserver / etcd / kube-scheduler / kube-controller-manager / kubelet / kube-proxy or CNI) がどこで動いているかを **目で見る**

## やること (予定)
1. `kind create cluster --image kindest/node:v1.33.x --config kind-config.yaml`
2. `kubectl cluster-info` / `kubectl get nodes -o wide`
3. `kubectl -n kube-system get pods` で static pod を眺める
4. `docker exec -it <cp-node> crictl ps` でランタイム側からも観察
5. `kubectl explain pod` の使い方

## TODO
- [ ] 共有 `kind-config.yaml` (Track A と共通)
- [ ] kubectl チートシート (旧 docker コマンド対応)
- [ ] `~/.kube/config` の説明

## 参考
- kubectl reference: https://kubernetes.io/docs/reference/kubectl/
- kind: https://kind.sigs.k8s.io/
