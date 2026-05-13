# 01 — Terraform で EKS 構築

## ゴール
- `terraform-aws-modules/eks/aws` **v20+** で EKS v1.33 を 1 ファイルで立ち上げ
- **Managed Node Group** (system pod 用、最小 2 台) を Spot 混在で
- **Access Entries** で自分の IAM ARN を `cluster-admin` に紐付け (もう aws-auth ConfigMap には触らない)
- **OIDC provider** を有効化 (Pod Identity 推奨だが、互換のため出しておく)
- managed addons: `vpc-cni` / `kube-proxy` / `coredns` / `eks-pod-identity-agent` / `aws-ebs-csi-driver`

---

## 🤔 なぜ必要？ (ストーリー)

> Track B では `kubeadm init` してから `kubectl get nodes` まで 1 時間かかった。
> EKS は **`terraform apply` を打って珈琲を 1 杯飲む間** に control-plane が立ち、`update-kubeconfig` を 1 回叩けば終わる。
>
> 「**面倒な所はクラウドに任せ、面白い所だけ自分で書く**」の最初の実感がここ。
> ただし「**お金が掛かるという自覚**」と「**消し方を先に書く**」をセットで。
>
> しかも `terraform-aws-modules/eks/aws` v20 は、過去の地獄 (aws-auth ConfigMap・自前 OIDC・自前 IAM Role for SA) を **module 引数 1 つで全部宣言的に** してくれる。これがマネージドの本当の意義。

## ✨ 面白いポイント (設計)

### 1. **Access Entries で aws-auth ConfigMap が消える**
> **痺れ所:** 「IAM Role / User をクラスタ管理者に追加」が `aws_eks_access_entry` リソース 1 個。
> `aws-auth` ConfigMap を kubectl で書き換えて syntax を壊し、**自分が締め出される** 古典的事故が消える。

### 2. **EKS Managed Node Group + Spot 混在**
> **痺れ所:** `capacity_type = "SPOT"` を 1 行入れるだけ。Karpenter 導入前の system 用 baseline はこれで十分。

### 3. **Addon は全部 module 引数で宣言**
> **痺れ所:** Pod Identity Agent / EBS CSI / CoreDNS / kube-proxy / VPC-CNI が、`cluster_addons = { ... }` 1 ブロックで version 固定可能。
> 後から helm install で散らからない (= GitOps しやすい)。

### 4. **OIDC provider はオマケで残す**
EKS Pod Identity を使うので IRSA は基本不要。ただし旧来 chart や OSS 互換のために OIDC provider URL は output しておく。

> **重要 (太字):** **EKS control plane だけで $0.10/h ≒ $2.4/日。学習中は夜に必ず destroy か、せめて node group を 0 にする。**

## 😱 あるある罠

- **VPC を新規で 1 つ作るので EIP 上限** (NAT GW 用) に当たる。`Service Quotas` を先に
- **Public subnet と Private subnet の tag** (`kubernetes.io/role/elb`, `kubernetes.io/role/internal-elb`) を忘れて ALB が subnet を見つけられない。module v20+ は自動で付くが、自前 VPC では要注意
- **AZ が 2 個しか無い region** で `subnet_ids` の数が足りない。`a/c/d` 等 3 AZ ある region を選ぶ
- **`terraform destroy` 前に LB / PVC を消し忘れ**: VPC が `DependencyViolation` で消せず無限ループ
- **Spot だけで system node group**: kube-proxy / coredns / VPC-CNI が SIGTERM で揺れて学習中の体験が悪い。**system は on-demand 1 + spot 1** くらいに

## やること

### 0. 準備

```bash
mkdir -p ~/work/k8s-bootcamp-eks && cd $_
aws sts get-caller-identity   # ← 自分の ARN をメモ。後で access entry に使う
export AWS_REGION=ap-northeast-1
```

### 1. `terraform/` を作る

ファイルは [`terraform/main.tf`](./terraform/main.tf) (本章に同梱) を参考に。
要点だけ抜粋:

```hcl
# terraform/versions.tf
terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.70" }
  }
}

provider "aws" {
  region = "ap-northeast-1"
  default_tags {
    tags = {
      Project = "k8s-bootcamp"
      Track   = "C"
    }
  }
}
```

```hcl
# terraform/vpc.tf
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = "bootcamp"
  cidr = "10.20.0.0/16"

  azs             = ["ap-northeast-1a", "ap-northeast-1c", "ap-northeast-1d"]
  private_subnets = ["10.20.1.0/24", "10.20.2.0/24", "10.20.3.0/24"]
  public_subnets  = ["10.20.101.0/24", "10.20.102.0/24", "10.20.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true   # ★ 学習用: 月 $45 を $45 (1 個) に抑える

  public_subnet_tags  = { "kubernetes.io/role/elb"          = 1 }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 }
}
```

```hcl
# terraform/eks.tf
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.24"

  cluster_name    = "bootcamp"
  cluster_version = "1.33"

  cluster_endpoint_public_access = true   # 学習用。本番は private + bastion

  enable_cluster_creator_admin_permissions = true  # ★ 自分を自動で admin 化
  authentication_mode                       = "API"  # access entries モード

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Pod Identity を有効化したいので OIDC は出力だけ取れれば OK
  enable_irsa = true

  cluster_addons = {
    vpc-cni                = { most_recent = true }
    kube-proxy             = { most_recent = true }
    coredns                = { most_recent = true }
    eks-pod-identity-agent = { most_recent = true }
    aws-ebs-csi-driver     = { most_recent = true }
  }

  eks_managed_node_groups = {
    system = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"   # system は安定優先
      min_size       = 2
      max_size       = 3
      desired_size   = 2
      labels         = { role = "system" }
      taints         = []            # アプリ Pod も乗せて良い (Karpenter 入る前提)
    }
  }

  tags = { Project = "k8s-bootcamp", Track = "C" }
}
```

```hcl
# terraform/outputs.tf
output "cluster_name"            { value = module.eks.cluster_name }
output "cluster_endpoint"        { value = module.eks.cluster_endpoint }
output "oidc_provider_arn"       { value = module.eks.oidc_provider_arn }
output "cluster_security_group"  { value = module.eks.cluster_security_group_id }
```

### 2. apply

```bash
cd terraform
terraform init
terraform plan -out plan.out
terraform apply plan.out
# 12〜15 分くらい (NAT GW + EKS control-plane が遅い)
```

### 3. kubeconfig 取得 + 動作確認

```bash
aws eks update-kubeconfig --name bootcamp --alias bootcamp-eks
kubectl get nodes -o wide
# NAME                                              STATUS   ROLES    VERSION
# ip-10-20-1-23.ap-northeast-1.compute.internal   Ready    <none>   v1.33.x
# ip-10-20-2-44.ap-northeast-1.compute.internal   Ready    <none>   v1.33.x

kubectl get pods -A
# kube-system 配下に coredns / aws-node (vpc-cni) / kube-proxy / eks-pod-identity-agent / ebs-csi が居る
```

### 4. PSA (Pod Security Admission) を namespace 単位で運用

EKS では cluster 全体の `AdmissionConfiguration` をいじれないので、**Namespace label で運用** が公式パターン。

```bash
kubectl create ns demo
kubectl label ns demo \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/warn=restricted \
  --overwrite
```

> ヒント: `kube-system` だけは `privileged` のまま (CNI 等が動かなくなるため)。

### 5. Access Entries の追加 (例: チームメンバー)

```hcl
# terraform/access.tf (例)
resource "aws_eks_access_entry" "teammate" {
  cluster_name  = module.eks.cluster_name
  principal_arn = "arn:aws:iam::123456789012:role/Developer"
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "teammate_view" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_eks_access_entry.teammate.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
  access_scope  { type = "cluster" }
}
```

`apply` 後、相手は `aws eks update-kubeconfig` だけでアクセスできる。**もう aws-auth ConfigMap を触らない**。

### 6. (オプション) 自分で OIDC 連携を確認

```bash
terraform output oidc_provider_arn
# arn:aws:iam::xxx:oidc-provider/oidc.eks.ap-northeast-1.amazonaws.com/id/XXXX
aws eks describe-cluster --name bootcamp --query "cluster.identity.oidc.issuer"
```

### 7. 後片付け (= 寝る前)

```bash
# Service type=LoadBalancer / Ingress が残っていると VPC が destroy できない
kubectl delete svc --all -A --field-selector spec.type=LoadBalancer
# 99-cleanup の手順で本格的に消す場合は:
# terraform destroy -auto-approve
```

> **節約 Tips:** 翌日も触る予定なら node group を `desired_size=0` に下げ、control-plane の $0.10/h だけに減らす:
> ```bash
> aws eks update-nodegroup-config --cluster-name bootcamp --nodegroup-name system \
>   --scaling-config minSize=0,maxSize=3,desiredSize=0
> ```

## やってみて気づくこと

- `terraform apply` 15 分で「control-plane + 2 ノード + 5 addon」が立つ世界の速さ
- `aws-auth` ConfigMap の手動編集を **一度もしていない** ことに気づく (それが正しい)
- Pod Identity Agent (`kube-system` の DaemonSet) が最初から居る → 04 章で使う
- `kubectl get nodes` の version が **`v1.33.x-eks-xxxxx`** という EKS 専用サフィックスになる

## 参考

- terraform-aws-modules/eks v20: https://github.com/terraform-aws-modules/terraform-aws-eks
- EKS Access Entries: https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html
- EKS Managed Node Groups: https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html
- EKS addons: https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html
- PSA on EKS: https://aws.github.io/aws-eks-best-practices/security/docs/pods/#pod-security-standards-pss-and-pod-security-admission-psa
