# 06 — Cilium / eBPF

## ゴール
- kind を **kube-proxy 無し** で起動し、Cilium を CNI として入れる
- **kube-proxy replacement** で Service ルーティングを eBPF に置き換える
- **Hubble** で L3/L4/L7 のフローを実時間で観察する
- **`CiliumNetworkPolicy` (L7)** で HTTP method 単位のポリシーを書く
- eBPF が「**カーネルにロードできる安全な VM**」であることを腹落ちさせる

---

## 🤔 なぜ必要？ (ストーリー)

> ある日、SRE が騒いでいる:「ノード 1 台で Service が 5000 個。`iptables -t nat -L` が 6 秒返ってこない」
> あなた:「kube-proxy が iptables モードだとリストが線形…?」
> → 確かに `iptables` バックエンドは Service 数に比例して **O(N) でルール挿入**。1 ルール挿入で **全テーブル再ロード**。秒単位で apiserver と乖離する。
>
> 別の日、開発者:「`curl service-a` が時々こけるんですけど、誰がどこに通信したか分かりますか?」
> あなた:「`tcpdump` を…どのノードで…どの veth で…」
> → Pod が再スケジュールされたら interface 名が変わる。**追跡できない**。
>
> 「**kube-proxy の iptables 限界**」と「**通信の不可視性**」 - この 2 つを **カーネルレベル** で解いたのが Cilium / eBPF です。
> kube-proxy を置き換え、Hubble で **L3 から L7 まで一発で見える**。

```
iptables kube-proxy : Service が増えると O(N) でルール挿入が遅くなる
        ↓
eBPF (Cilium KPR)   : ハッシュマップで O(1)。Pod 再スケジュールに追従
```

## ✨ 面白いポイント (設計)

### 1. **eBPF = "カーネル内の安全な VM"**

eBPF は **検証器** (verifier) を持つ仮想命令セット。プログラムを load する時に:

- ループが必ず終わるか
- メモリ越境がないか
- 許可された helper のみ呼ぶか

を **静的検証** → 通った時だけカーネルに JIT。カーネル再起動なしで「フック点」(syscall / tc / XDP) にロードできる。

> **痺れ所:** カーネルモジュールを書かずに、カーネル内で動く高速コードを **動的に差し込める**。kubelet も sshd も、走らせたままでネットワークを書き換えられる。

### 2. **kube-proxy replacement (KPR)**

```
kube-proxy (iptables) : Service A → iptables NAT chain を辿る (O(N))
        ↓
Cilium KPR (eBPF)     : socket() / connect() の時点で eBPF が backend IP を選ぶ (O(1))
```

NAT が **socket layer** で起きるので、Pod 内では「最初から backend と直接話している」ように見える。**conntrack 経由しない**ので CPU も少ない。

### 3. **`CiliumNetworkPolicy` で L7 ポリシー**

標準 `NetworkPolicy` は L3/L4 (IP / Port) しか書けない。Cilium は **Envoy を sidecarless で差し込む** ことで:

```yaml
- toEndpoints: [{matchLabels: {app: api}}]
  toPorts:
    - ports: [{port: "80"}]
      rules:
        http:
          - method: "GET"
            path: "/healthz"
```

「GET /healthz だけ通す」が書ける。

> **痺れ所:** mTLS や JWT 検証もポリシーで書ける。Service Mesh 相当のことが **sidecar なし** で出来る。

### 4. **Hubble = "クラスタ全体の tcpdump"**

eBPF が記録したフローを Hubble が UI 化:

```
podA → podB  TCP/80  FORWARDED  policy-verdict:allowed
podC → podB  TCP/80  DROPPED    policy-verdict:denied (no rule)
```

**誰が誰に話したか / 誰が落とされたか** が時系列で見える。これがあるとポリシー作成のフィードバックループが激変する。

## 😱 あるある罠

- **既存の kind に後から Cilium を入れる**: kube-proxy が動いている状態で KPR を有効にすると iptables ルールが残って **二重書き換え** に。**この章は専用クラスタ** で
- **`networking.disableDefaultCNI: false` のまま**: kind デフォルトの kindnetd が動き、Cilium と喧嘩する。必ず `disableDefaultCNI: true`
- **`kube-proxy` を残したまま KPR を `true`**: 競合して通信が壊れる。`kubeProxyMode: "none"` 必須
- **Hubble UI を NodePort で晒す**: 認証なし。**port-forward 限定** で
- **L7 ポリシー時の `dnsPolicy`**: Cilium DNS proxy が DNS を見る前に Pod が外に出てしまうと L7 が効かない。`dnsPolicy: ClusterFirst` を確認
- **kind v1.33 + Cilium バージョン**: 古い Cilium だと cgroup v2 まわりでハマる。**Cilium v1.16+** 推奨

## やること

> **重要:** この章は `01-cluster-up` のクラスタとは **別クラスタ** を作ります。kube-proxy 無しで起動する必要があるため。

### 0. 準備 — kind を kube-proxy 無しで作る

```yaml
# kind-cilium.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ciliumlab
networking:
  disableDefaultCNI: true        # kindnetd を無効に
  kubeProxyMode: "none"          # kube-proxy を入れない
  podSubnet:     "10.244.0.0/16"
  serviceSubnet: "10.96.0.0/16"
nodes:
  - role: control-plane
    extraPortMappings:
      - {containerPort: 80,  hostPort: 80}
      - {containerPort: 443, hostPort: 443}
  - role: worker
  - role: worker
```

```bash
kind create cluster --config kind-cilium.yaml --image kindest/node:v1.33.0
kubectl config use-context kind-ciliumlab

# 確認: CNI が無いので CoreDNS は Pending のまま
kubectl get pods -A
# → coredns が Pending、Node が NotReady でも正常。CNI を入れれば動く
```

### 1. Cilium install (KPR 有効)

`cilium-cli` を使う方法:

```bash
API_SERVER_IP=$(docker inspect ciliumlab-control-plane \
  -f '{{.NetworkSettings.Networks.kind.IPAddress}}')

cilium install --version 1.16.5 \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=${API_SERVER_IP} \
  --set k8sServicePort=6443 \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true

cilium status --wait
# Cilium:             OK
# Operator:           OK
# Hubble Relay:       OK
# KubeProxyReplacement:  True   [eth0 ...]
```

```bash
# Service ルーティングが eBPF に置き換わっていることを確認
kubectl -n kube-system exec ds/cilium -- cilium status | grep -i 'kubeproxy'
# KubeProxyReplacement:    True   [...]

# iptables の Service NAT が無いことを確認
docker exec ciliumlab-control-plane iptables -t nat -S KUBE-SERVICES 2>&1 | head -3
# → 空、または Chain 自体がない (= kube-proxy の置き換え成功)
```

### 2. アプリと Service を立てる

```bash
kubectl create ns ch06-cilium
kubectl label ns ch06-cilium pod-security.kubernetes.io/enforce=baseline --overwrite
```

```yaml
# apps.yaml
apiVersion: apps/v1
kind: Deployment
metadata: {name: api, namespace: ch06-cilium}
spec:
  replicas: 2
  selector: {matchLabels: {app: api}}
  template:
    metadata: {labels: {app: api}}
    spec:
      containers:
        - name: hello
          image: nginxdemos/hello:plain-text
          ports: [{containerPort: 80}]
---
apiVersion: v1
kind: Service
metadata: {name: api, namespace: ch06-cilium}
spec:
  selector: {app: api}
  ports: [{port: 80, targetPort: 80}]
---
apiVersion: v1
kind: Pod
metadata:
  name: client
  namespace: ch06-cilium
  labels: {app: client}
spec:
  containers:
    - name: c
      image: curlimages/curl:8.10.1
      command: ["sleep", "infinity"]
```

```bash
kubectl apply -f apps.yaml
kubectl -n ch06-cilium wait --for=condition=Ready pods --all --timeout=120s

# Service が eBPF で解決されることを確認
kubectl -n ch06-cilium exec client -- curl -s http://api/ | head -3
```

### 3. Hubble で通信を可視化

```bash
cilium hubble enable --ui
cilium hubble ui &           # → http://localhost:12000 が開く
# (CI 上などで開けない場合は手動 port-forward)
# kubectl -n kube-system port-forward svc/hubble-ui 12000:80
```

別ターミナルで流し見:

```bash
cilium hubble port-forward &
hubble observe --namespace ch06-cilium -f
# → client → api の FORWARDED フローがリアルタイム表示
```

`client` から何回か叩く:

```bash
for i in $(seq 1 5); do
  kubectl -n ch06-cilium exec client -- curl -s -o /dev/null -w "%{http_code}\n" http://api/
done
```

Hubble UI で **service graph** にエッジが描かれる。

### 4. L7 ポリシー: GET /healthz だけ許す

`nginxdemos/hello` は `/` を返すが、`/healthz` を擬似的に試すために `/?healthz` でも試せる。ここでは **method** に絞った L7 を試す:

```yaml
# cnp-l7.yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: api-l7-readonly
  namespace: ch06-cilium
spec:
  endpointSelector:
    matchLabels: {app: api}
  ingress:
    - fromEndpoints:
        - matchLabels: {app: client}
      toPorts:
        - ports:
            - {port: "80", protocol: TCP}
          rules:
            http:
              - method: "GET"
                path: "/.*"
```

```bash
kubectl apply -f cnp-l7.yaml

# GET は通る
kubectl -n ch06-cilium exec client -- curl -s -o /dev/null -w "GET %{http_code}\n" http://api/
# POST は L7 ポリシーで拒否される
kubectl -n ch06-cilium exec client -- curl -s -o /dev/null -w "POST %{http_code}\n" -X POST http://api/
# → POST 403 (Cilium L7 proxy が落とす)
```

Hubble で対応する `policy-verdict:denied` フローが見えるはず:

```bash
hubble observe --namespace ch06-cilium --verdict DROPPED -f
```

> **痺れ所:** Pod は **無改造** (sidecar なし)。Cilium が裏で Envoy を動かして L7 を読んでいる。

### 5. (発展) Cilium Gateway API

Track A 04 で Envoy Gateway を使ったが、Cilium だけでも Gateway API 実装になれる:

```bash
helm upgrade cilium oci://docker.io/cilium/cilium --version 1.16.5 \
  --reuse-values -n kube-system \
  --set gatewayAPI.enabled=true

kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml
# あとは 04 章と同じ HTTPRoute が、GatewayClassName: cilium で動く
```

時間があれば 04 章の `apps.yaml` を流用して試す。

### 6. 後片付け

```bash
kubectl delete ns ch06-cilium
kind delete cluster --name ciliumlab
# → Cilium ごとクラスタ廃棄が一番速い
```

> 元のクラスタ (`kind-kind` 等) に戻る:
> ```bash
> kubectl config use-context kind-kind
> ```

## やってみて気づくこと

- `iptables -t nat -L` が **空** なのに Service が動く違和感 (= eBPF が裏で全部やっている)
- Hubble UI で **どの Pod がどの Pod と話しているか** が一目で分かる。tcpdump の苦行が嘘のよう
- L7 ポリシーが **sidecar 無し** で効くのが新鮮 (Istio 経験者ほど驚く)
- KPR は **conntrack を経由しない** ので、`conntrack -L` の数も激減する
- 「ポリシーを書き間違えて全部落ちた」も Hubble の `DROPPED` が即座に教えてくれる

## 参考

- Cilium: https://docs.cilium.io/
- Hubble: https://github.com/cilium/hubble
- eBPF 全体像: https://ebpf.io/what-is-ebpf/
- kube-proxy replacement: https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/
- L7 policies: https://docs.cilium.io/en/stable/security/policy/language/#layer-7-examples
- Cilium Gateway API: https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/
- AdminNetworkPolicy: https://network-policy-api.sigs.k8s.io/
