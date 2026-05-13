# 02 — kubeadm Bootstrap (containerd + registry.k8s.io)

## ゴール
- control-plane で `kubeadm init`、worker で `kubeadm join`
- v1.22 時代との差分を体験:
  - **dockershim 廃止** → ランタイムは containerd 1.7+
  - **`registry.k8s.io`** が default
  - **ServiceAccount token の自動 Secret 作成廃止**
  - **PSA を AdmissionConfiguration で cluster default にする**

## やること (予定)
1. `kubeadm-config.yaml` (clusterConfiguration + KubeletConfiguration + AdmissionConfiguration)
2. `kubeadm init --config kubeadm-config.yaml --upload-certs`
3. `crictl ps` でランタイムを確認 (`docker` は無い)
4. worker で `kubeadm join`
5. `kubectl get pods -n kube-system` で `registry.k8s.io/...` を確認

## TODO
- [ ] `kubeadm-config.yaml` (PSA `baseline` を cluster default)
- [ ] join token 生成 / 再発行手順
- [ ] cgroup driver 確認 (`systemd` 推奨)
- [ ] etcd 単体観察 (`crictl exec` で etcdctl)

## 参考
- https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/
- PSA AdmissionConfiguration: https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-admission-controller/
