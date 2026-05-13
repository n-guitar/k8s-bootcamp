# 00 — Prerequisites (Track C)

## ゴール
- AWS アカウント / CLI / Terraform / kubectl / helm を **Track C で動く版** に揃える
- IAM の **最小権限戦略** を決める (Admin で短時間 vs 個別ポリシー)
- **料金感** を先に把握: EKS control plane は **存在するだけで $0.10/h ≒ 月 $73**
- 予算アラート (Budgets) と **タグ戦略** (`Project=k8s-bootcamp / Track=C`) を最初に設計

---

## 🤔 なぜ必要？ (ストーリー)

> あなたは Track B で素の k8s を組み立て、「kubelet / etcd / CNI / kube-proxy が全部分かった」感を得た。
> でも本番で毎晩 etcd snapshot を取り、API server の証明書をローテートし、CNI plugin の OOM を 3 時頃に直すのは違う。
>
> 「**面倒な所はクラウドに任せ、面白い所だけ自分で書く**」のがマネージドの本懐。
> その最初の一歩は「**金が掛かるという自覚**」と「**消し方を先に決める**」こと。
>
> Track B では PC の電源を切ればコストは 0 だった。
> Track C は **Pod が 1 つも動いていない深夜 3 時にも $0.10/h** が課金される世界です。

## ✨ 面白いポイント (設計)

### 1. **EKS Access Entries (2023/12 GA)**
> **痺れ所:** 旧来の `aws-auth` ConfigMap (kubectl から直接編集して破壊) は **死語**。
> 今は `aws eks create-access-entry` (= AWS API + Terraform resource) で IAM → k8s RBAC が宣言的に紐付く。

### 2. **Tag を先に決める**
> **痺れ所:** EKS / EBS / ELB / Karpenter EC2 / EFS / ECR — 後から全部の残骸を tag で grep できるかが運命。
> `Project=k8s-bootcamp` `Track=C` `Owner=<your-name>` を **全リソース** に。

### 3. **Budgets + Cost Explorer**
> **痺れ所:** Free Tier の EKS は **無い**。「やった、寝かしておこう」が 1 週間で $20。先に **$10 で alert** を仕込む。

## 😱 あるある罠

- **`AdministratorAccess` の長期キーで作業**: 漏れたら破滅。**SSO + 短期 STS** か、最低でも MFA 必須
- **region 違い**: console は ap-northeast-1 を見ているのに CLI は us-east-1 を叩いていた。`aws configure get region` で確認
- **VPC / EIP の上限**: 既存 VPC が多い AWS アカウントだと limit に当たる。先に Service Quotas を見る
- **`terraform destroy` 前に `kubectl delete svc`** を忘れて、**LB だけ残って課金継続**
- **kubectl の version skew**: v1.33 cluster に v1.27 kubectl で `--field-selector` が動かない、など

## やること

### 0. AWS アカウントの下準備

- **専用 sandbox account** を強く推奨 (本番 / 共用 account ではやらない)
- ルートユーザは封印、**IAM Identity Center (SSO)** か少なくとも IAM User + MFA
- **AWS Budgets**: 月 $20 で email alert を仕込む

```bash
# 例: ap-northeast-1 を既定リージョンに
aws configure set region ap-northeast-1
aws sts get-caller-identity   # ← 自分が誰として叩いているか必ず確認
```

### 1. CLI ツール群

| ツール | バージョン目安 | 用途 |
|---|---|---|
| AWS CLI | v2.15+ | `aws eks update-kubeconfig`, IAM, ECR login |
| Terraform | v1.7+ | 全インフラ宣言 |
| kubectl | **v1.33.x** | API skew は ±1 マイナーまで |
| helm | v3.14+ | controller の install |
| eksctl | (任意) | Terraform を使うので必須ではない。観察用 |
| cosign | v2.4+ | 07 章で使う |
| jq / yq | 最新 | 趣味 |

```bash
# macOS (Homebrew) の例
brew install awscli terraform kubectl helm jq yq cosign

# Linux の例 (kubectl)
curl -LO "https://dl.k8s.io/release/v1.33.0/bin/linux/amd64/kubectl"
sudo install -m 0755 kubectl /usr/local/bin/kubectl

aws --version
terraform -version
kubectl version --client
helm version
```

> **注意:** v1.33 cluster には **kubectl v1.32 〜 v1.34** が公式サポート範囲。古い kubectl は静かに API を取りこぼします。

### 2. IAM 戦略 (短時間 Admin or 絞り込み)

学習用途では **「短時間だけ Admin で動かす」が現実的**。長期キーで Admin は危険。

- 推奨: **IAM Identity Center (SSO) → PowerUser + IAM/EKS 管理権限**
- 妥協案: IAM User + Admin + **MFA 必須ポリシー** + 1 日で revoke
- 本気で最小権限を目指す場合は以下の管理ポリシー群が起点:
  - `AmazonEKSClusterPolicy`, `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`
  - `AmazonEC2FullAccess`, `IAMFullAccess`, `AmazonVPCFullAccess`
  - `AWSCloudFormationFullAccess` (Karpenter v1 は CFn を使う場合がある)

### 3. Tag 戦略 (**最重要**)

全 Terraform module に `default_tags` を入れる。後で消し残しを `resourcegroupstaggingapi` で探すための保険。

```hcl
# terraform/provider.tf (テンプレ)
provider "aws" {
  region = "ap-northeast-1"
  default_tags {
    tags = {
      Project = "k8s-bootcamp"
      Track   = "C"
      Owner   = "your-name"
      Env     = "sandbox"
    }
  }
}
```

確認コマンド (後の章 / cleanup で頻出):

```bash
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Project,Values=k8s-bootcamp Key=Track,Values=C \
  --query 'ResourceTagMappingList[].ResourceARN' --output table
```

### 4. 料金見積もり (Track C をフルで起動した場合)

> **太字で注意:** **EKS control plane は存在するだけで $0.10/h。寝かせ忘れ厳禁。**

| 項目 | 単価 | 1 日 (8h 起動) | 1 ヶ月 (常時) |
|---|---|---|---|
| EKS control plane | $0.10/h | **$0.80** | **$73** |
| Managed Node (t3.medium ×2 on-demand) | $0.0416/h ×2 | $0.67 | $61 |
| Karpenter Spot (m6i.large ×0〜2) | ~$0.03/h | $0.24 | ~$22 |
| ALB | $0.0225/h + LCU | $0.18 | $16.5+ |
| NAT Gateway (1 AZ) | $0.062/h + データ | $0.50 | $45 |
| EFS (10 GB) | $0.36/GB-月 | — | $3.6 |
| ECR ストレージ (5 GB) | $0.10/GB-月 | — | $0.5 |

> **目安:** **8h 起動で 1 日 $3 前後** / 常時起動だと **月 $200 超**。
> **必ず毎晩 `99-cleanup` の手順で `terraform destroy`** か、最低でも node group を 0 にする。

### 5. AWS Budgets を 5 分で

```bash
# 月 $20 で 80% 到達時に email
aws budgets create-budget --account-id "$(aws sts get-caller-identity --query Account --output text)" \
  --budget '{
    "BudgetName": "k8s-bootcamp-monthly",
    "BudgetLimit": {"Amount": "20", "Unit": "USD"},
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST"
  }' \
  --notifications-with-subscribers '[{
    "Notification": {"NotificationType":"ACTUAL","ComparisonOperator":"GREATER_THAN","Threshold":80},
    "Subscribers": [{"SubscriptionType":"EMAIL","Address":"you@example.com"}]
  }]'
```

### 6. kubeconfig 切替の運用 (multi-cluster 対策)

複数 cluster (Track A の kind と Track C の EKS) を行き来するので、**alias を分ける**。

```bash
# 01 章で実 cluster ができたあと
aws eks update-kubeconfig --name bootcamp --alias bootcamp-eks
kubectl config get-contexts
kubectl config use-context bootcamp-eks
```

`kubectx` / `kubens` を入れておくと事故が減る。

### 7. 動作確認 (準備完了の合図)

```bash
aws sts get-caller-identity                   # 自分の ARN が出る
aws ec2 describe-regions --output table       # API は通る
terraform -version                             # v1.7+
kubectl version --client --output=yaml        # v1.33.x client
helm version                                   # v3.14+
```

### 8. 後片付け

この章自体は何も作らないので片付け不要。**Budgets だけは残す** こと。

## やってみて気づくこと

- "AWS は **何もしなくても課金されている** 物がある" (EKS control plane / NAT GW / EIP / EBS など)
- Tag を最初に決めれば、後から `tag-editor` だけで全リソースが見える
- `aws sts get-caller-identity` を打つ癖は **事故の 9 割を防ぐ**
- Identity Center (SSO) の短期トークンは慣れると **長期キーには戻れない**

## 参考

- EKS pricing: https://aws.amazon.com/eks/pricing/
- Access Entries: https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html
- AWS Budgets: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html
- Service Quotas (VPC / EIP): https://docs.aws.amazon.com/general/latest/gr/aws_service_limits.html
