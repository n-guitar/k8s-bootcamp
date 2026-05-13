# 03 — CNI: Cilium + kube-proxy replacement

## ゴール
kube-proxy をインストールせず、**Cilium が kube-proxy を置き換える** 構成を作る。Hubble で観察。

## やること (予定)
1. `kubeadm init` 時に `--skip-phases=addon/kube-proxy` を指定 (前章で済ませてもよい)
2. `cilium install --version <v> --set kubeProxyReplacement=true --set k8sServiceHost=<cp-ip> --set k8sServicePort=6443`
3. `cilium status` で kube-proxy free を確認
4. Hubble Relay + UI を入れる
5. NetworkPolicy / CiliumNetworkPolicy で L7 制御

## TODO
- [ ] `cilium-values.yaml`
- [ ] SG で health check ポートの開放
- [ ] Hubble UI への port-forward 手順

## 参考
- Cilium on kubeadm: https://docs.cilium.io/en/stable/installation/k8s-install-kubeadm/
- kube-proxy replacement: https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/
