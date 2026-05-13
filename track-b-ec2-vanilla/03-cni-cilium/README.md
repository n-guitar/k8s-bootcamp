# 03 — CNI: Cilium で kube-proxy も置き換える

## ゴール
- Cilium v1.16 を helm で導入し、`NotReady` の Node を `Ready` にする
- **kube-proxy を入れずに**、Cilium が **eBPF で Service VIP の負荷分散** をやることを確認
- Hubble (Relay + UI) で Pod 間通信を **目で見る**
- CiliumNetworkPolicy で L7 (HTTP method 制御) を試す

---

## 🤔 なぜ必要？ (ストーリー)

> kubeadm は CNI を入れない。
> ドキュメントには **「ネットワーク・プラグインはあなたが選んでください」** と書いてあるだけ。
> これは設計思想であり、放置ではない:「**ネットワークは要件次第なので強制しない**」。
>
> 数ある CNI の中で Cilium が突き抜けている理由は 3 つ:
> 1. **iptables を捨てて eBPF** で Service / NetworkPolicy をやる (= kube-proxy が要らない)
> 2. **L7 で policy** が書ける (`HTTP GET /api/healthz` だけ許可、みたいな)
> 3. **Hubble** で Pod-to-Pod 通信が **絵で見える** (`tcpdump` の代わり)
>
> 「kube-proxy はもう iptables で 1 万行を捌ききれない」「Pod 間通信が誰にも見えない」 — これらの 2010 年代の不満を eBPF で一気に解いたのが Cilium。

## ✨ 面白いポイント (設計)

### 1. **kubeProxyReplacement: eBPF が Service を実装する**

従来:

```
client → iptables KUBE-SVC-XXX → KUBE-SEP-YYY → Pod IP
```

kube-proxy が `iptables-restore` で数千行のルールを撒いていた。

Cilium:

```
client → eBPF map lookup → Pod IP  (カーネル内で O(1))
```

eBPF プログラムが **socket layer で書き換える** ので、パケットが iptables の長い chain を抜ける必要すらない。

> **痺れ所:** "**iptables の置き換え**" ではなく "**iptables を必要としない**" のが本質。
> Linux カーネル 5.x で eBPF が成熟したから、k8s のネットワーク層を **コードで再実装** することが可能になった。

### 2. **CNI plugin は "Pod 起動時に呼ばれる shell 規約"**

`/etc/cni/net.d/05-cilium.conf` が置かれ、kubelet は Pod 作成時に CNI plugin (binary) を呼ぶ。
plugin は **stdin で JSON を受け取り、stdout に JSON を返す** だけ。

```
kubelet → CNI ADD → /opt/cni/bin/cilium-cni → eBPF map に IP を書く
```

> **痺れ所:** "CNI" は **巨大なプロトコルではなく、たった 4 動詞 (ADD, DEL, CHECK, VERSION) の shell 規約**。
> だから Cilium / Calico / Flannel / AWS VPC CNI が **同じ抜き差し穴** で共存できる。

### 3. **Hubble = "**eBPF で観測しているからオーバーヘッドが小さい**"**

Hubble は Cilium の datapath にぶら下がって flow を抜き出す。
別途 `tcpdump` を Pod に仕込む必要が無い。
**Service 名 / Pod ラベル / L7 verb** まで見える ("pod=frontend → svc=api : HTTP GET /healthz : OK").

## 😱 あるある罠

- **kube-proxy を残したまま Cilium 入れる**: 両方が iptables を書き合う or eBPF と被って fail。前章で `--skip-phases=addon/kube-proxy` してある
- **`k8sServiceHost` を指定しない**: kubeProxyReplacement で API server に到達できなくなる (kube-proxy が無いから VIP `10.96.0.1` が解決できない)。**control-plane の Private IP** を指定する
- **MTU mismatch**: VPC が 9001 (Jumbo) なのに Cilium が 1450 のままで断片化。`MTU=8951` 程度を明示
- **SG で 8472/udp (VXLAN) や 4240/tcp (health) を閉じている**: 前章で self-allow にしてあれば OK
- **`cilium status` の "kube-proxy free" を見ずに OK 判定**: kubectl get pods だけ見て安心しがち

## やること

### 0. 準備

```bash
export KUBECONFIG=$PWD/../02-kubeadm-bootstrap/kubeconfig
kubectl get nodes
# 全 Node が NotReady のはず (CNI 無し)

cd ../01-terraform-vpc-ec2/terraform
export CP_PRIVATE=$(terraform output -raw cp_private_ip)
cd -
echo "CP_PRIVATE=$CP_PRIVATE"
```

### 1. helm で Cilium を入れる

`manifests/cilium-values.yaml`:

```yaml
kubeProxyReplacement: true
k8sServiceHost: __CP_PRIVATE__
k8sServicePort: 6443

ipam:
  mode: kubernetes      # Pod CIDR は kubeadm が割り当てる
routingMode: tunnel
tunnelProtocol: vxlan

hubble:
  enabled: true
  relay:
    enabled: true
  ui:
    enabled: true

operator:
  replicas: 1            # 学習用、本番は 2

# 観測しやすく
debug:
  enabled: false
```

```bash
helm repo add cilium https://helm.cilium.io/
helm repo update

sed "s/__CP_PRIVATE__/${CP_PRIVATE}/g" manifests/cilium-values.yaml > /tmp/cilium-values.yaml

helm install cilium cilium/cilium \
  --version 1.16.5 \
  --namespace kube-system \
  --values /tmp/cilium-values.yaml
```

### 2. ready になるのを確認

```bash
kubectl -n kube-system rollout status ds/cilium --timeout=5m
kubectl get nodes
# 全 Node が Ready
```

`cilium status` (cilium-cli):

```bash
cilium status --wait
#  Kube-proxy free: true       ← ここを見る
#  ClusterMesh: disabled
#  Cilium: Ok 3/3 reachable
#  ...
```

### 3. eBPF が Service を解決しているかを覗く

任意の cilium Pod に入って:

```bash
POD=$(kubectl -n kube-system get pod -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}')
kubectl -n kube-system exec -it $POD -c cilium-agent -- cilium service list | head
# ID   Frontend          Service Type   Backend
# 1    10.96.0.1:443     ClusterIP      1 => 10.0.0.x:6443 (kube-apiserver)
# ...
```

→ kube-proxy が居ないのに `10.96.0.1:443` (kubernetes Service VIP) が解決されている。

### 4. Hubble UI を開く

```bash
cilium hubble enable --ui    # 既に values で enabled なら no-op
kubectl -n kube-system port-forward svc/hubble-ui 12000:80
# http://localhost:12000 をブラウザで開く
```

別 terminal で観測対象を作る:

```bash
kubectl create ns demo
kubectl -n demo create deploy hello --image=nginxdemos/hello:plain-text --replicas=2
kubectl -n demo expose deploy hello --port=80
kubectl run -n demo curl --image=curlimages/curl:8.10.1 -it --rm --restart=Never -- \
  sh -c 'for i in $(seq 1 20); do curl -s http://hello/; sleep 1; done'
```

Hubble UI の `demo` namespace で Pod 間 flow が **緑のグラフ** で流れる。

### 5. L7 policy を書く (Cilium ならでは)

```yaml
# manifests/l7-policy.yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: hello-l7
  namespace: demo
spec:
  endpointSelector:
    matchLabels:
      app: hello
  ingress:
    - fromEndpoints:
        - matchLabels:
            run: curl
      toPorts:
        - ports: [{port: "80", protocol: TCP}]
          rules:
            http:
              - method: "GET"
                path: "/"
```

```bash
kubectl apply -f manifests/l7-policy.yaml

# GET / は通る
kubectl run -n demo curl2 --image=curlimages/curl:8.10.1 --labels=run=curl -it --rm --restart=Never -- \
  curl -sS -o /dev/null -w '%{http_code}\n' http://hello/

# POST / は 403 で蹴られる (Cilium が L7 で蹴る)
kubectl run -n demo curl3 --image=curlimages/curl:8.10.1 --labels=run=curl -it --rm --restart=Never -- \
  curl -sS -o /dev/null -w '%{http_code}\n' -X POST http://hello/
# → 403
```

> NetworkPolicy (L3/L4) では出来ない HTTP メソッド制限が、CiliumNetworkPolicy では **eBPF + Envoy proxy** で実現されている。

### 6. 後片付け (章をまたぐ時は残す)

```bash
kubectl delete ns demo
# Cilium 自体は残す (次章以降でも必要)
```

## やってみて気づくこと

- **CNI を入れて初めて Node が Ready になる**: k8s は "ネットワークが無いと Pod が動かない" を素直に表現している
- kube-proxy を **入れないでクラスタが動く** という事実が、eBPF 時代の到来を体感させる
- `cilium service list` の中身は、まさに **kube-proxy が iptables で書いていたものの eBPF 版**
- Hubble は "**Pod-to-Pod 通信の Datadog**" であり、本番運用でも入れて損は無い
- CNI は **shell 規約** なので、Cilium ↔ Calico ↔ AWS VPC CNI の入れ替えはクラスタ作り直しに近いが、概念は同じ穴で抜き差し

## 参考
- Cilium on kubeadm: https://docs.cilium.io/en/stable/installation/k8s-install-kubeadm/
- kube-proxy replacement: https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/
- CNI spec: https://github.com/containernetworking/cni/blob/main/SPEC.md
- Hubble: https://docs.cilium.io/en/stable/observability/hubble/
- CiliumNetworkPolicy: https://docs.cilium.io/en/stable/security/policy/
