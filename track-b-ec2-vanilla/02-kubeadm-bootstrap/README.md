# 02 — kubeadm で素のクラスタを Bootstrap する

## ゴール
- control-plane で `kubeadm init`、worker で `kubeadm join` を実行
- **kube-proxy を作らない** (次章で Cilium が置換、`--skip-phases=addon/kube-proxy`)
- `/etc/kubernetes/manifests/` の **static Pod** を目で見る
- PSA (`baseline`) を **cluster-wide default** で有効化
- kubeconfig を手元に持ち帰り `kubectl get nodes` が通る

---

## 🤔 なぜ必要？ (ストーリー)

> EKS や GKE は `eks create-cluster` を 1 発叩けば 10 分後にクラスタが立つ。
> でも、その 10 分の間に **何が走っているのか** を言える人は意外と少ない。
>
> kubeadm を手で叩くと、**1 コマンドごとに静かに何かが配置される** のがわかる:
> - CA が作られる (`/etc/kubernetes/pki/ca.crt`)
> - kube-apiserver / etcd / scheduler / controller-manager の YAML が **kubelet が見るディレクトリに置かれるだけ** (`/etc/kubernetes/manifests/`)
> - kubelet が `containerd` 経由でその Pod を立ち上げる
> - bootstrap token が発行され、worker はそれを使って **join 時に証明書を発行してもらう**
>
> "**kubeadm は魔法ではなく、kubelet にお膳立てするツール**" だと体感するのが本章。

## ✨ 面白いポイント (設計)

### 1. **static Pod = "kubelet がディレクトリを polling する" だけ**

`kube-apiserver` が無いと普通の Pod は作れない (etcd が無いから)。
**鶏と卵問題** を、kubelet が `/etc/kubernetes/manifests/*.yaml` を **直接読む** ことで解決している。

```
kubelet 起動
  ↓ poll /etc/kubernetes/manifests/
  ↓ etcd.yaml を見つける → containerd で起動
  ↓ kube-apiserver.yaml を見つける → containerd で起動
  ↓ scheduler / controller-manager も同様
  ↓ ここで初めて "通常の" k8s 機能が立ち上がる
```

> **痺れ所:** kubelet にとって static Pod は **API server 不要で動かせる例外** であり、それゆえ control-plane 自身に使われている。
> マネージドサービスでは見えない "**ブートの根っこ**" がここにある。

### 2. **PKI 一式を kubeadm が 1 発で発行する**

```
/etc/kubernetes/pki/
├── ca.crt / ca.key                  ← cluster CA
├── apiserver.crt                    ← kube-apiserver 用 server cert
├── apiserver-kubelet-client.crt     ← apiserver → kubelet
├── front-proxy-ca.crt               ← aggregator
├── etcd/ca.crt                      ← etcd 用、独立 CA
└── sa.key / sa.pub                  ← ServiceAccount トークン署名鍵
```

> **痺れ所:** k8s は **マルチ CA** 構造。"kube-apiserver の通信用" と "etcd 用" を別 CA にしているのは、片方の漏洩で全滅しないため。
> ここを自分の目で見たことがあると、`x509: certificate signed by unknown authority` のトラブルで頭が回るようになる。

### 3. **bootstrap token で worker が参加する**

`kubeadm join <cp>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>` の中で起きていること:

1. worker は token で API server に **匿名 + 弱認証** で繋がる
2. API server が `csr` を受理し、TLS Bootstrapping で **kubelet 自身の証明書** を発行
3. worker の kubelet はその cert で正規メンバーになる

> "**初対面の VM を、限定権限の使い捨てパスワードで仲間に入れる**" という、現代的なゼロタッチ思想。

### 4. **Cilium に道を譲るため kube-proxy を作らない**

`--skip-phases=addon/kube-proxy` を `kubeadm init` に渡すと、kube-proxy DaemonSet は配備されない。
これを次章で Cilium の `kubeProxyReplacement=true` が引き継ぐ。

## 😱 あるある罠

- **swap が有効 / cgroup driver 不一致**: `kubeadm init` の preflight で蹴られる。前章で潰したはず
- **SG の 6443 が閉じている**: worker から `kubeadm join` が timeout する。Node 間は self-reference で全開放してある (前章)
- **`--apiserver-advertise-address` を public IP に設定**: 動くが kube-apiserver の証明書 SAN に public IP が入らず後で詰む。**Private IP** にする
- **`kubectl` を root で叩いてしまう**: `KUBECONFIG=/etc/kubernetes/admin.conf` のまま忘れる。`$HOME/.kube/config` にコピーする手順を踏む
- **join token を平文で git push**: 24h で expire するが、ハッシュ込みなら一時的にとはいえ侵入経路になる
- **PSA を後から `restricted` でいきなり enforce**: kube-system 系 Pod が動かなくなる。`baseline` を default にし、kube-system だけ exempt

## やること

### 0. 準備

前章の `terraform apply` が完了し、3 ノードの `cloud-init` が `done` になっていること。
control-plane の Private IP を控えておく:

```bash
cd ../01-terraform-vpc-ec2/terraform
export CP_PUBLIC=$(terraform output -raw cp_public_ip)
export CP_PRIVATE=$(terraform output -raw cp_private_ip)
export WORKERS=( $(terraform output -json worker_public_ips | jq -r '.[]') )
echo "cp=$CP_PUBLIC / private=$CP_PRIVATE"
echo "workers=${WORKERS[@]}"
```

### 1. control-plane に kubeadm 設定を送り込む

`manifests/kubeadm-config.yaml` (テンプレート、`__CP_PRIVATE__` を後で sed する):

```yaml
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: __CP_PRIVATE__
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///run/containerd/containerd.sock
  kubeletExtraArgs:
    - name: node-ip
      value: __CP_PRIVATE__
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: v1.32.0
controlPlaneEndpoint: "__CP_PRIVATE__:6443"
networking:
  podSubnet: 10.244.0.0/16
  serviceSubnet: 10.96.0.0/12
apiServer:
  extraArgs:
    - name: admission-control-config-file
      value: /etc/kubernetes/admission/admission-config.yaml
  extraVolumes:
    - name: admission-config
      hostPath: /etc/kubernetes/admission
      mountPath: /etc/kubernetes/admission
      readOnly: true
      pathType: DirectoryOrCreate
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
# Cilium が置換するので kube-proxy 自体は作らないが、念のため
mode: ""
```

`manifests/admission-config.yaml` (PSA を cluster default に):

```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
  - name: PodSecurity
    configuration:
      apiVersion: pod-security.admission.config.k8s.io/v1
      kind: PodSecurityConfiguration
      defaults:
        enforce: "baseline"
        enforce-version: "latest"
        audit:   "restricted"
        audit-version: "latest"
        warn:    "restricted"
        warn-version: "latest"
      exemptions:
        usernames: []
        runtimeClasses: []
        namespaces: ["kube-system"]
```

control-plane に scp:

```bash
sed "s/__CP_PRIVATE__/${CP_PRIVATE}/g" manifests/kubeadm-config.yaml > /tmp/kubeadm-config.yaml
scp -i ~/.ssh/k8s-bootcamp /tmp/kubeadm-config.yaml ubuntu@${CP_PUBLIC}:/tmp/
scp -i ~/.ssh/k8s-bootcamp manifests/admission-config.yaml ubuntu@${CP_PUBLIC}:/tmp/
```

### 2. control-plane で `kubeadm init`

```bash
ssh -i ~/.ssh/k8s-bootcamp ubuntu@${CP_PUBLIC} bash <<'EOF'
set -euo pipefail
sudo mkdir -p /etc/kubernetes/admission
sudo cp /tmp/admission-config.yaml /etc/kubernetes/admission/admission-config.yaml

sudo kubeadm init \
  --config /tmp/kubeadm-config.yaml \
  --skip-phases=addon/kube-proxy \
  --upload-certs | tee /tmp/kubeadm-init.log
EOF
```

出力末尾の `kubeadm join ... --token ... --discovery-token-ca-cert-hash sha256:...` を控える。

### 3. kubeconfig を手元にコピー

```bash
ssh -i ~/.ssh/k8s-bootcamp ubuntu@${CP_PUBLIC} 'sudo cat /etc/kubernetes/admin.conf' > ./kubeconfig
# server を public IP に差し替え (手元 PC から繋ぐため)
sed -i.bak "s|server: https://${CP_PRIVATE}:6443|server: https://${CP_PUBLIC}:6443|" ./kubeconfig
export KUBECONFIG=$PWD/kubeconfig

kubectl get nodes
# NAME              STATUS     ROLES           AGE   VERSION
# ip-10-0-0-xxx     NotReady   control-plane   1m    v1.32.x
```

> `NotReady` なのは **CNI がまだ無い** から。次章で Cilium を入れると Ready になる。

### 4. static Pod を目で見る

```bash
ssh -i ~/.ssh/k8s-bootcamp ubuntu@${CP_PUBLIC} \
  'sudo ls /etc/kubernetes/manifests/'
# etcd.yaml  kube-apiserver.yaml  kube-controller-manager.yaml  kube-scheduler.yaml

ssh -i ~/.ssh/k8s-bootcamp ubuntu@${CP_PUBLIC} \
  'sudo crictl --runtime-endpoint unix:///run/containerd/containerd.sock ps'
# kube-apiserver / etcd / kube-controller-manager / kube-scheduler が動いている
# docker は存在しない
```

PKI:

```bash
ssh -i ~/.ssh/k8s-bootcamp ubuntu@${CP_PUBLIC} 'sudo ls /etc/kubernetes/pki/'
# apiserver.crt, ca.crt, etcd/, front-proxy-ca.crt, sa.pub ...
```

### 5. worker を join する

control-plane で再発行 (出力をそのまま使えるよう):

```bash
JOIN_CMD=$(ssh -i ~/.ssh/k8s-bootcamp ubuntu@${CP_PUBLIC} 'sudo kubeadm token create --print-join-command')
echo "$JOIN_CMD"
```

各 worker で実行:

```bash
for w in "${WORKERS[@]}"; do
  ssh -i ~/.ssh/k8s-bootcamp ubuntu@${w} "sudo $JOIN_CMD"
done
```

確認:

```bash
kubectl get nodes
# NAME              STATUS     ROLES           AGE   VERSION
# ip-10-0-0-xxx     NotReady   control-plane   5m    v1.32.x
# ip-10-0-0-yyy     NotReady   <none>          1m    v1.32.x
# ip-10-0-0-zzz     NotReady   <none>          1m    v1.32.x
```

### 6. PSA が効いていることを確認

```bash
kubectl create ns ch02-test
cat <<'EOF' | kubectl -n ch02-test apply -f -
apiVersion: v1
kind: Pod
metadata: {name: priv}
spec:
  containers:
    - name: c
      image: busybox:1.36
      securityContext: { privileged: true }
      command: ["sleep", "3600"]
EOF
# → Error from server (Forbidden): pods "priv" is forbidden:
#   violates PodSecurity "baseline:latest": privileged
```

cluster default が `baseline` (kube-system は exempt) になっている。

### 7. etcd を覗く (発展)

```bash
ssh -i ~/.ssh/k8s-bootcamp ubuntu@${CP_PUBLIC} bash <<'EOF'
sudo crictl --runtime-endpoint unix:///run/containerd/containerd.sock \
  exec -it $(sudo crictl ps --name etcd -q) \
  etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/namespaces/default -w json | head -c 400
EOF
```

→ etcd には k8s の "望む状態" が **JSON で生で** 入っている、を目視。

### 8. 後片付け

このまま 03 章 (Cilium) へ進む。中断するなら EC2 を `stop` または `terraform destroy`。

> **AWS 料金注意:** Bootstrap 後も EC2 は走り続けます。寝る前は **必ず stop** か destroy。

## やってみて気づくこと

- control-plane の正体は **kubelet + 4 つの YAML + PKI**。それ以上でも以下でもない
- "クラスタを作る" は **CA を発行する** + **kubelet を仕込む** + **worker を bootstrap token で迎え入れる** の 3 つに分解できる
- マネージドが隠しているのは **PKI / etcd / static Pod の運用**。本章を一度やると EKS の挙動の "なぜ" が読めるようになる
- PSA を cluster-wide で default 設定するには **AdmissionConfiguration ファイル** を kube-apiserver にマウントする必要がある (namespace ラベルだけでは不十分)

## 参考
- kubeadm Create cluster: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/
- kubeadm config (v1beta4): https://kubernetes.io/docs/reference/config-api/kubeadm-config.v1beta4/
- PSA AdmissionConfiguration: https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-admission-controller/
- static Pod: https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/
- kubelet TLS bootstrapping: https://kubernetes.io/docs/reference/access-authn-authz/kubelet-tls-bootstrapping/
