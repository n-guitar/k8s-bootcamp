# 02 — Karpenter (Node Autoscaling のパラダイムシフト)

## ゴール
- **Karpenter v1.x (`karpenter.sh/v1`)** で `NodePool` / `EC2NodeClass` を 1 セット書く
- 旧来の Cluster Autoscaler (ASG ベース) との **発想の違い** を体感
- **Spot + On-Demand 混在** で fall-back を仕込み、Spot 中断耐性を確認
- `consolidationPolicy: WhenEmptyOrUnderutilized` で **アイドル node が自動で消える** ことを目視
- Pod Identity で Karpenter 自身の権限を管理 (IRSA は使わない)

---

## 🤔 なぜ必要？ (ストーリー)

> Cluster Autoscaler 時代: 「`Pending` Pod が出てから ASG が `DesiredCapacity` を +1 し、EC2 が起動し、kubelet が join するまで **3〜10 分**」。
> しかも ASG は **事前に instance type を 1〜数個に固定** する設計。複数 instance family を混ぜると ASG が増殖し、Spot 中断時の挙動が雑になる。
>
> Karpenter は **ASG を完全に取り払う**。
> 1. `Pending` Pod を見る
> 2. その requests と nodeSelector / taint からピッタリな EC2 instance type を **その場で選ぶ** (数百種の中から)
> 3. RunInstances で直接 launch → kubelet が join
>
> **15〜60 秒で `Ready`**。ASG は要らない。これは **Node 管理のパラダイムシフト** です。

## ✨ 面白いポイント (設計)

### 1. **Pending Pod から逆算する Node 設計**
> **痺れ所:** 「先に何台用意するか」ではなく、「**いま居る Pod に必要なちょうど良い EC2 は何か**」を毎秒考える発想。
> requests=4Gi の Pod 5 個が来たら `m6i.xlarge` 1 台で済むかも、と Karpenter が **算数する**。

### 2. **Spot + On-Demand を 1 つの NodePool で混ぜる**
> **痺れ所:** `requirements` に `karpenter.sh/capacity-type In [spot, on-demand]` と書くだけで **prefer-spot, fallback-on-demand**。
> Spot が枯渇すれば自動で On-Demand に。ASG だと別 ASG を 2 つ用意して優先度を組む必要があった。

### 3. **Consolidation (アイドルの自動圧縮)**
> **痺れ所:** `consolidationPolicy: WhenEmptyOrUnderutilized` で「より小さい instance に詰め直せるなら自動で詰め直す」。
> アプリを scale down → Karpenter が **大きな EC2 を捨てて小さな EC2 に置き換える**。コスト最適化が自動。

### 4. **EC2NodeClass で AMI / SubnetSelector を分離**
> **痺れ所:** `NodePool` (= ワークロード方針) と `EC2NodeClass` (= AWS インフラ詳細) が **責務分離**。
> AMI を AL2023 から Bottlerocket に切り替え、は `EC2NodeClass` 1 つの編集で済む。

> **重要 (太字):** **Karpenter は本気で EC2 を立てます。NodePool の `limits.cpu` を必ず設定し、暴走に備える。学習中の限界値は CPU 50 / memory 100Gi 程度に。**

## 😱 あるある罠

- **Pod Identity Association を `karpenter` SA に紐付け忘れ** → Karpenter が `UnauthorizedOperation` で動かない
- **`EC2NodeClass.subnetSelectorTerms` の tag が VPC subnet に付いていない** → "No subnets matched" で Pending のまま
- **AL2023 vs AL2 vs Bottlerocket の AMI alias を混同**: `alias: al2023@latest` が今の推奨
- **`disruption.budgets` 未設定で大量 deprovision** → 一気に Node が落ちて Pod が雪崩
- **`requirements` で SSD/networking 等を絞り過ぎ** → 候補 instance が無くなり Karpenter が静かに諦める
- **System node group の taint と被って `karpenter` controller 自体が schedule 不能**: Karpenter は **system MNG** に必ず居場所を残す

## やること

### 0. 準備

01 章で EKS が立っていること、`kubectl` が EKS を向いていること。

```bash
kubectl config use-context bootcamp-eks
kubectl get nodes   # system MNG が 2 台 Ready
```

### 1. Karpenter 用 IAM (Terraform)

`terraform-aws-modules/eks/aws` の **submodule `karpenter`** が IAM / SQS / Pod Identity を作る:

```hcl
# terraform/karpenter.tf
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.24"

  cluster_name          = module.eks.cluster_name
  enable_pod_identity   = true                   # ★ IRSA ではなく Pod Identity
  create_pod_identity_association = true

  # Karpenter が EC2 を launch する際にこの Role を付ける (NodeIAMRole)
  node_iam_role_use_name_prefix = false
  node_iam_role_name            = "karpenter-node-${module.eks.cluster_name}"
  create_node_iam_role          = true
}

output "karpenter_queue_name"          { value = module.karpenter.queue_name }
output "karpenter_node_iam_role_name"  { value = module.karpenter.node_iam_role_name }
output "karpenter_node_iam_role_arn"   { value = module.karpenter.node_iam_role_arn }
```

```bash
cd terraform && terraform apply
```

### 2. Karpenter 本体を helm install (OCI chart)

```bash
helm registry logout public.ecr.aws 2>/dev/null || true
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version 1.0.7 \
  --namespace karpenter --create-namespace \
  --set "settings.clusterName=bootcamp" \
  --set "settings.interruptionQueue=$(terraform -chdir=terraform output -raw karpenter_queue_name)" \
  --set "controller.resources.requests.cpu=200m" \
  --set "controller.resources.requests.memory=512Mi" \
  --wait
kubectl -n karpenter get pods
```

> Pod Identity Association が module で作られているので、`serviceAccount.annotations` (IRSA 用) は不要。

### 3. `EC2NodeClass` と `NodePool`

[`manifests/karpenter-nodepool.yaml`](./manifests/karpenter-nodepool.yaml) を参照。要点:

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiFamily: AL2023
  amiSelectorTerms:
    - alias: al2023@latest      # ★ v1 で導入: AMI 名を hard-code しない
  role: "karpenter-node-bootcamp"
  subnetSelectorTerms:
    - tags: { "kubernetes.io/role/internal-elb": "1" }   # private subnets
  securityGroupSelectorTerms:
    - tags: { "aws:eks:cluster-name": "bootcamp" }
  tags:
    Project: k8s-bootcamp
    Track: C
    karpenter.sh/discovery: bootcamp
---
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    metadata:
      labels: { provisioner: karpenter }
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      requirements:
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["c", "m", "r"]
        - key: karpenter.k8s.aws/instance-cpu
          operator: In
          values: ["2", "4", "8"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]    # ★ prefer spot, fallback on-demand
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
      expireAfter: 720h   # 30 日で Node ローテーション (脆弱性 patch)
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m
    budgets:
      - nodes: "10%"     # 一度に 10% しか壊さない
  limits:
    cpu: "50"            # ★ 暴走防止: NodePool 全体で 50 vCPU まで
    memory: "100Gi"
```

```bash
kubectl apply -f manifests/karpenter-nodepool.yaml
kubectl get nodepools,ec2nodeclasses
```

### 4. 大量 Pod を投げて起動を観察

```yaml
# manifests/inflate.yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: inflate, namespace: default }
spec:
  replicas: 0
  selector: { matchLabels: { app: inflate } }
  template:
    metadata: { labels: { app: inflate } }
    spec:
      nodeSelector: { provisioner: karpenter }   # ★ Karpenter 専用に隔離
      containers:
        - name: pause
          image: public.ecr.aws/eks-distro/kubernetes/pause:3.9
          resources:
            requests: { cpu: "1", memory: "1.5Gi" }
```

```bash
kubectl apply -f manifests/inflate.yaml
kubectl scale deploy/inflate --replicas=20

# 別ターミナルで観察
kubectl get nodes -L karpenter.sh/capacity-type -L node.kubernetes.io/instance-type -w
kubectl -n karpenter logs -l app.kubernetes.io/name=karpenter -f --tail=50
```

→ **15〜60 秒** で `Ready` の Spot Node が複数台 join する。**`capacity-type=spot`** がほとんどのはず。

### 5. アイドル時間で自動 deprovision

```bash
kubectl scale deploy/inflate --replicas=0
# 1〜2 分待つ
kubectl get nodes -L karpenter.sh/capacity-type
# → Karpenter が起こした node が消えて、system MNG の 2 台だけが残る
```

### 6. Spot 中断のリハーサル (オプション)

`fis` (Fault Injection Simulator) で 1 台を中断:

```bash
NODE=$(kubectl get nodes -l karpenter.sh/capacity-type=spot -o name | head -1)
INSTANCE_ID=$(kubectl get $NODE -o jsonpath='{.spec.providerID}' | awk -F/ '{print $NF}')
echo "would interrupt: $INSTANCE_ID  (本気でやる場合は FIS から)"
```

Karpenter が SQS interruption queue を 2 分前通知で受け取り、Pod を退避 → 別 Node に schedule、を観察できる。

### 7. 後片付け

```bash
kubectl delete -f manifests/inflate.yaml
kubectl delete -f manifests/karpenter-nodepool.yaml
# Karpenter 自体は残しても課金は controller pod 程度 (system node に同居)
```

## やってみて気づくこと

- ASG が **1 つも無い** のに Node が自由に増減する不思議な感覚
- `kubectl describe pod` の event に `Karpenter` が **直接** Pod を schedule して Node を立てているログが出る
- Pending → Ready が **1 分以内**。これに慣れると CA には戻れない
- `consolidationPolicy` がアイドル node を **粛々と捨てる** ので、夜中に課金が勝手に下がる

## 参考

- Karpenter docs: https://karpenter.sh/
- v1 API migration: https://karpenter.sh/v1.0/upgrading/v1-migration/
- EKS Best Practices: https://aws.github.io/aws-eks-best-practices/karpenter/
- Pod Identity Association: https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html
