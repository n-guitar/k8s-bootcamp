# 05 — kubeadm Upgrade (v1.32 → v1.33)

## ゴール
1 マイナーバージョン上げ (`v1.32.x` → `v1.33.x`) を、control-plane → worker の順に **ローリング** で実施。失敗時のロールバック手順も確認。

## やること (予定)
1. `kubeadm upgrade plan` で確認
2. control-plane で `kubeadm upgrade apply`
3. `kubectl drain <node>` → `apt upgrade kubelet kubectl` → uncordon
4. worker も同様に 1 台ずつ
5. `kubectl get nodes` で全ノードが v1.33 になることを確認

## TODO
- [ ] バージョンスキュー (kubelet と apiserver の許容差) のメモ
- [ ] CRI / CNI のアップグレード可否
- [ ] etcd backup を取ってから実施

## 参考
- https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/
- Version skew policy: https://kubernetes.io/releases/version-skew-policy/
