# 05 — kubeadm でローリングアップグレード (v1.32 → v1.33)

## ゴール
- `kubeadm upgrade plan` でアップグレード可否を確認する手順を身体で覚える
- **control-plane → worker** の順に、**1 台ずつ drain しながら** マイナーバージョンを 1 つ上げる
- バージョンスキュー (kubelet と kube-apiserver の許容差) を意識する
- 失敗時のロールバック / etcd backup の取り方も押さえる

---

## 🤔 なぜ必要？ (ストーリー)

> Kubernetes は **4 ヶ月に 1 マイナー** リリースされる。
> サポートは N-2 (3 リリース) しかない。つまり **1 年に 1〜2 回はアップグレードしないと EOL**。
>
> ところが本番運用者の永遠の悩みは:
> - **upgrade 中に service が落ちないか?**
> - **API が deprecate されていないか?**
> - **CNI / CSI / etcd は付いてくるか?**
>
> EKS だと "Upgrade ボタン" を押せばマネージドがやってくれるが、内部で起きていることは kubeadm の **`upgrade plan / apply` + drain ループ** と本質的に同じ。
> 本章で一度手で踏むと、マネージドの挙動が「**そういうことをやっている**」と読めるようになる。

## ✨ 面白いポイント (設計)

### 1. **kubeadm upgrade = "**static Pod の manifest を書き換える**"**

`kubeadm upgrade apply v1.33.0` がやっていること:

1. `/etc/kubernetes/manifests/kube-apiserver.yaml` の `image:` を v1.33.0 に書き換える
2. kubelet が manifest 変更を検知して、新しい version の Pod に **roll する**
3. 同じことを controller-manager / scheduler / etcd にも実施

> **痺れ所:** "**Pod の image を書き換えれば update できる**" という Kubernetes 自身の設計を、**Kubernetes 自身のアップグレードに使っている**。再帰的で美しい。

### 2. **バージョンスキュー: kubelet は apiserver より N-3 まで古くて良い**

| component | スキュー許容 |
|---|---|
| kube-apiserver どうし (HA) | 同一 | minor |
| kubelet | apiserver より **最大 3 minor 古くて良い** |
| kubectl | apiserver の ±1 minor |
| kube-proxy / controller-manager / scheduler | apiserver と同一 minor |

> **痺れ所:** "**control-plane を先に上げ、worker は数 minor 遅れても良い**" がポリシーで保証されている。
> = 大規模クラスタで **段階的にローリング** することが可能。

### 3. **drain は PDB を見る**

`kubectl drain <node>` は、Pod に紐付く **PodDisruptionBudget** を尊重する:

```
PDB(minAvailable=2)   → そのアプリの Pod が 2 以下になる drain は **拒否**
```

= 「**運用中のアプリが SLO を割らない**」ことが drain の前提に組み込まれている。

## 😱 あるある罠

- **etcd backup を取らずに upgrade**: 失敗時に詰む。**`etcdctl snapshot save`** を毎回取る
- **CRD / API の deprecation を見落とす**: v1.32 で `flowcontrol.apiserver.k8s.io/v1beta3` が消える等。**`kubeadm upgrade plan` の出力** を必ず読む
- **同時に複数 Node を drain**: PDB 違反でアプリが落ちる。**1 台ずつ**
- **kubelet を `apt-mark hold` したまま**: `apt upgrade kubelet` がスキップされる。一度 `unhold` → install → 再 `hold`
- **CNI を放置**: Cilium が v1.16 のままで k8s が v1.33 になっても多くの場合は動くが、release notes は必ず確認

## やること

### 0. 準備: 現状の確認

```bash
export KUBECONFIG=$PWD/../02-kubeadm-bootstrap/kubeconfig
kubectl get nodes
# 全 Node が v1.32.x で Ready

cd ../01-terraform-vpc-ec2/terraform
export CP=$(terraform output -raw cp_public_ip)
mapfile -t WORKERS < <(terraform output -json worker_public_ips | jq -r '.[]')
cd -
KEY=~/.ssh/k8s-bootcamp
```

### 1. etcd snapshot を取る (保険)

```bash
ssh -i $KEY ubuntu@$CP bash <<'EOF'
set -e
ETCD_POD=$(sudo crictl --runtime-endpoint unix:///run/containerd/containerd.sock ps --name etcd -q | head -1)
sudo crictl --runtime-endpoint unix:///run/containerd/containerd.sock exec $ETCD_POD \
  etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    snapshot save /tmp/etcd-snap-$(date +%s).db
sudo ls -la /tmp/etcd-snap-*.db
EOF
# 余裕があれば scp で手元に持ってくる
```

### 2. control-plane で `kubeadm upgrade plan`

まず apt repository を `v1.33` に切り替え、新しい kubeadm だけ入れる:

```bash
ssh -i $KEY ubuntu@$CP bash <<'EOF'
set -e
sudo sed -i 's|/v1\.32/|/v1.33/|' /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm=1.33.*-* || sudo apt-get install -y kubeadm
sudo apt-mark hold kubeadm
kubeadm version
sudo kubeadm upgrade plan
EOF
```

`upgrade plan` の出力で:
- どのコンポーネントが上がるか
- 削除される API があるか
- CRD migration が要るか
を確認。

### 3. control-plane を upgrade

```bash
ssh -i $KEY ubuntu@$CP \
  'sudo kubeadm upgrade apply -y v1.33.0'
```

裏で起きていること:
- `/etc/kubernetes/manifests/*.yaml` の image が v1.33 系に書き換わる
- kubelet が manifest 変更を検出 → 順次新 Pod に置き換え
- etcd も新 image に

### 4. control-plane の kubelet / kubectl を上げる

```bash
# control-plane を cordon + drain (自身を退避)
kubectl cordon $(kubectl get node -l node-role.kubernetes.io/control-plane -o name)
kubectl drain $(kubectl get node -l node-role.kubernetes.io/control-plane -o name | sed 's|node/||') \
  --ignore-daemonsets --delete-emptydir-data

ssh -i $KEY ubuntu@$CP bash <<'EOF'
set -e
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=1.33.*-* kubectl=1.33.*-* || sudo apt-get install -y kubelet kubectl
sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload
sudo systemctl restart kubelet
EOF

kubectl uncordon $(kubectl get node -l node-role.kubernetes.io/control-plane -o name | sed 's|node/||')
kubectl get nodes
# control-plane が v1.33 になる
```

### 5. worker を 1 台ずつ upgrade

```bash
for i in "${!WORKERS[@]}"; do
  W=${WORKERS[$i]}
  NODE=$(ssh -i $KEY ubuntu@$W 'hostname')
  echo "==== upgrading $NODE ($W) ===="

  # drain
  kubectl drain $NODE --ignore-daemonsets --delete-emptydir-data --force

  ssh -i $KEY ubuntu@$W bash <<'EOF'
set -e
sudo sed -i 's|/v1\.32/|/v1.33/|' /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-mark unhold kubeadm kubelet kubectl
sudo apt-get install -y kubeadm=1.33.*-* || sudo apt-get install -y kubeadm
# kubeadm が node 用の設定を更新
sudo kubeadm upgrade node
sudo apt-get install -y kubelet=1.33.*-* kubectl=1.33.*-* || sudo apt-get install -y kubelet kubectl
sudo apt-mark hold kubeadm kubelet kubectl
sudo systemctl daemon-reload
sudo systemctl restart kubelet
EOF

  kubectl uncordon $NODE
  kubectl get nodes
done
```

### 6. 全ノードが v1.33 か確認

```bash
kubectl get nodes -o wide
# VERSION 列が全て v1.33.x

kubectl version
# Server Version: v1.33.x
```

### 7. アプリが落ちなかったかを観察

drain 中に Pod の events を別 terminal で:

```bash
kubectl get events -A --watch
# Evicted / Killing / Created / Started のシーケンスが流れる
```

PDB を仕込んだ Deployment があれば、drain が **意図的に待つ** ことも観察できる。

### 8. ロールバック (失敗した場合)

- **upgrade plan 段階で失敗**: 何も変わっていないので apt を v1.32 に戻すだけ
- **upgrade apply 中に止まった**: kubeadm が manifest を書き換え途中の可能性。再度 `kubeadm upgrade apply v1.33.0` で続行
- **etcd 自体が壊れた**: 上で取った snapshot から `etcdctl snapshot restore` で復旧 (本書では割愛、k8s docs を参照)

### 9. 後片付け (このまま 06 へ)

そのまま続行。中断するなら EC2 を stop か destroy。

> **AWS 料金注意:** upgrade 作業中に EBS が増えることは無いが、EC2 は走り続けます。

## やってみて気づくこと

- "アップグレード" の正体は **container image の roll** + **kubelet binary の置換**。それを全 Node で繰り返すだけ
- **drain → upgrade → uncordon** の 3 ステップが全 Node で共通。スクリプト化が容易
- マネージドのアップグレードボタンも、内側ではほぼ同じことをやっている (+ AWS 側で AMI を作り直して Node Group を rolling replace)
- バージョンスキューを意識すると、**control-plane 先行 / worker 追従** という運用パターンが自然に出てくる

## 参考
- kubeadm upgrade: https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/
- Version skew policy: https://kubernetes.io/releases/version-skew-policy/
- Deprecated APIs: https://kubernetes.io/docs/reference/using-api/deprecation-guide/
- etcd backup/restore: https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/
