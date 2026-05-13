# 06 — Node Lifecycle (drain / cordon / 追加 / kubelet flag)

## ゴール
本物の EC2 ならではの「ノードを 1 台増やす / 退避する / kubelet を再設定する」操作を一通り。

## やること (予定)
1. Terraform に worker を 1 台追加 (`count = 3`) → `kubeadm join`
2. `kubectl cordon` → `kubectl drain --ignore-daemonsets --delete-emptydir-data`
3. kubelet config を `KubeletConfiguration` で書き換え (例: `--seccomp-default=true`)
4. systemd で `kubelet` 再起動 → `kubectl describe node` で確認
5. (発展) In-place Pod Resize (`kubectl patch --subresource=resize`) を試す

## TODO
- [ ] PodDisruptionBudget で drain がブロックされる例
- [ ] kubelet config drop-in の場所
- [ ] In-place resize の前提条件 (Pod の resizePolicy)

## 参考
- In-place Pod Resize: https://kubernetes.io/blog/2023/05/12/in-place-pod-resize-alpha/
- KubeletConfiguration: https://kubernetes.io/docs/reference/config-api/kubelet-config.v1beta1/
