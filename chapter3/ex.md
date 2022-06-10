# Pod,Deployment,Service,Namesapceの操作


## (前準備) Kubectlコマンドの補完 & エイリアス
```sh
$ source <(kubectl completion bash)
$ echo "source <(kubectl completion bash)" >> ~/.bashrc
$ alias k=kubectl
$ complete -F __start_kubectl k
```

## (前準備) kubernetes clusterの情報確認
```sh
# master-node、worker-nodeがそれぞれ1台以上Readyとなっていること
$ k get nodes -o wide
NAME            STATUS   ROLES                  AGE   VERSION    INTERNAL-IP      EXTERNAL-IP   OS-IMAGE       KERNEL-VERSION      CONTAINER-RUNTIME
master-node     Ready    control-plane,master   17h   v1.22.10   192.168.200.10   <none>        Ubuntu 21.10   5.13.0-22-generic   cri-o://1.22.5
worker-node01   Ready    worker                 17h   v1.22.10   192.168.200.11   <none>        Ubuntu 21.10   5.13.0-22-generic   cri-o://1.22.5

```
