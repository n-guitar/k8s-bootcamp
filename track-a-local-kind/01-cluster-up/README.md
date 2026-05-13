# 01 — Cluster Up (kind multi-node + crictl)

## ゴール
- kind で control-plane×1 / worker×2 のクラスタを起動
- ノード内に入って **containerd / crictl** を体験 (dockershim 撤廃後のデファクト)
- `registry.k8s.io` 由来のイメージで構成されていることを確認

## やること (予定)
1. `kind-config.yaml` を書く (3 ノード, extraPortMappings 80/443, kubeadm patches で PSA admissionConfiguration を仕込む)
2. `kind create cluster --image kindest/node:v1.33.x --config kind-config.yaml`
3. `docker exec -it <node-container> crictl ps` でコンテナ確認
4. `kubectl get pods -A -o jsonpath=...` で `k8s.gcr.io` 参照が無いことを確認

## TODO
- [ ] `kind-config.yaml`
- [ ] `scripts/up.sh`, `scripts/down.sh`
- [ ] crictl チートシート (旧 docker コマンド対応表)

## 参考
- KEP-2221 cri-containerd: https://kubernetes.io/blog/2022/02/17/dockershim-faq/
- crictl: https://kubernetes.io/docs/tasks/debug/debug-cluster/crictl/
