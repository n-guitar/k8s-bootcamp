# 00 — Prerequisites (Track B / AWS EC2)

## ゴール
- AWS CLI v2 / Terraform / kubectl / helm / cilium-cli が手元で動くこと
- 学習用 IAM ユーザ (または Role) を **必要最小限の権限** で用意
- **Billing アラート** を先に仕掛けて、寝落ちでも数千円で止まる体制
- すべての AWS リソースに `Project=k8s-bootcamp` / `Track=B` の **タグ規約** を決める
- リージョンを 1 つに固定 (本書は `us-east-1` 前提だが variable で差し替え可能)

---

## 🤔 なぜ必要？ (ストーリー)

> あなたは Track 0 / Track A で kind の上に Kubernetes を動かしてきた。
> 今度は **本物の Linux VM** の上に kubeadm でクラスタを組む。
> 当然 EC2 課金が発生する。
>
> 「ちょっと試して寝るだけ」のつもりが、`terraform destroy` を忘れて翌週請求が来る — これは **誰もが 1 度は通る道** です。
> しかも EBS や NAT Gateway や Elastic IP は **EC2 を消しても残る** ので、コンソールから手で消すと取り残しが必ず出ます。
>
> だから Track B は最初に **「課金の蛇口」を 2 重に締める** ところから始める。
> - 入口で IAM 権限を絞る (= 事故を小さく)
> - 出口で Billing アラート + タグ運用 (= 取り残しを発見可能に)

## ✨ 面白いポイント (設計)

### 1. **タグだけが横断検索の頼り**

AWS は VPC / EC2 / EBS / SG / EIP / NAT / Snapshot ... と **リソースの種類が爆発的に多い**。
コンソールで 1 種類ずつ巡回するのは現実的ではない。横串で検索できる唯一の手段が **タグ**。

```
Project = k8s-bootcamp
Track   = B
```

> **痺れ所:** Resource Groups Tagging API (`aws resourcegroupstaggingapi get-resources`) を **全 region** で叩くと、
> "このタグの付いたリソース" を一覧できる。 cleanup の最終確認はこれ。
> Terraform で `default_tags` を使えば、書き忘れは構造的に発生しない。

### 2. **IAM は学習用でも最小権限**

学習用だからと AdministratorAccess を渡すと、credentials が漏れた瞬間 RDS や Route53 まで触られる。
本書では `AmazonEC2FullAccess` / `AmazonVPCFullAccess` / `IAMReadOnlyAccess` を中心に組む。

> **痺れ所:** "最小権限" の実装に IAM Policy / Permissions Boundary / SCP の **3 階層** があるのが AWS の世界観。
> k8s 側 RBAC との対比で見ると、設計思想が並行進化していることがわかる。

### 3. **Billing アラートは "事後で良い情報" だが先に作る**

CloudWatch Billing Alarm は **us-east-1 でしか作れない** (歴史的経緯)。
$10 / $50 / $100 など段階で SNS → email を仕込むと、寝落ちしてもメールで起きられる。

## 😱 あるある罠

- **root アカウントの credentials を `aws configure`**: 漏れたら全部終わり。**IAM ユーザを必ず作る**
- **`~/.aws/credentials` を git に push**: `pre-commit` で `gitleaks` を仕込むのが本気の対策
- **NAT Gateway を立てて寝る**: $0.045/h × 24h ≒ **月 $32**。Track B ではあえて NAT を **使わない構成**
- **EBS Snapshot の消し忘れ**: スナップショットは **ボリュームを消しても残る**。料金は安いが永遠に増える
- **複数 region に散らばる**: 必ず 1 region に固定。CloudShell から叩く時は `AWS_REGION` 環境変数で

## やること

### 0. 準備: ツールを揃える

| ツール | バージョン | 入れ方 (例) |
|---|---|---|
| AWS CLI v2 | 2.15+ | `brew install awscli` / 公式 zip |
| Terraform  | 1.7+  | `brew install terraform` / `tfenv` |
| kubectl    | v1.33 系 | `brew install kubectl` |
| helm       | v3.14+ | `brew install helm` |
| cilium-cli | v0.16+ | `brew install cilium-cli` |
| jq / yq    | 任意   | `brew install jq yq` |
| ssh        | OpenSSH | OS 同梱 |

確認:

```bash
aws --version
terraform version
kubectl version --client
helm version --short
cilium version --client
```

### 1. AWS 認証情報を用意する

ベストは **IAM Identity Center (SSO)**。組織アカウントが無い人は IAM ユーザでも良いが、その場合も MFA を有効化。

```bash
# SSO の場合
aws configure sso
# IAM ユーザの場合
aws configure
```

確認:

```bash
aws sts get-caller-identity
# {
#   "UserId": "AIDA...",
#   "Account": "1234...",
#   "Arn": "arn:aws:iam::1234...:user/k8s-bootcamp"
# }
```

### 2. 学習用 IAM ユーザの最小権限 (例)

```bash
aws iam create-user --user-name k8s-bootcamp
aws iam attach-user-policy --user-name k8s-bootcamp \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
aws iam attach-user-policy --user-name k8s-bootcamp \
  --policy-arn arn:aws:iam::aws:policy/AmazonVPCFullAccess
aws iam attach-user-policy --user-name k8s-bootcamp \
  --policy-arn arn:aws:iam::aws:policy/IAMReadOnlyAccess
# 04 章 (EBS CSI) で追加の policy を attach する
```

> **本番に持っていく時はこれでは足りません**。Permissions Boundary で「これより強くなるな」と上限を貼り、SCP で組織レベルの禁止行為を縛るのが定石。

### 3. リージョンとタグ規約を決める

```bash
export AWS_REGION=us-east-1
export AWS_DEFAULT_REGION=us-east-1
```

Terraform 側 (次章) では:

```hcl
provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project = "k8s-bootcamp"
      Track   = "B"
      Owner   = var.owner   # 例: "alice"
    }
  }
}
```

### 4. Billing アラートを **us-east-1** に作る

```bash
aws sns create-topic --name k8s-bootcamp-billing --region us-east-1
# 表示された TopicArn にメールを subscribe
aws sns subscribe --region us-east-1 \
  --topic-arn arn:aws:sns:us-east-1:<acct>:k8s-bootcamp-billing \
  --protocol email --notification-endpoint you@example.com
```

CloudWatch アラーム ($10 / $50 / $100 で 3 段) — まず $10 だけ:

```bash
aws cloudwatch put-metric-alarm --region us-east-1 \
  --alarm-name k8s-bootcamp-billing-10usd \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1 --period 21600 --statistic Maximum \
  --threshold 10 --namespace "AWS/Billing" --metric-name EstimatedCharges \
  --dimensions Name=Currency,Value=USD \
  --alarm-actions arn:aws:sns:us-east-1:<acct>:k8s-bootcamp-billing
```

Billing データの公開は事前に有効化が必要 (コンソール: Billing → Billing preferences → "Receive Billing Alerts")。

### 5. SSH 鍵を作る (Session Manager を使うなら省略可)

```bash
ssh-keygen -t ed25519 -C "k8s-bootcamp" -f ~/.ssh/k8s-bootcamp
# 公開鍵を Terraform に変数として渡す
cat ~/.ssh/k8s-bootcamp.pub
```

> **本番では SSH ではなく SSM Session Manager** が定石 (鍵管理が消える、Audit が取れる)。
> 本トラックでは初学者が `crictl` や `journalctl` を直接叩く体験を重視するため SSH を採用していますが、Track 上級者は SSM への切替を強く推奨。

### 6. バージョン確認スクリプト

`scripts/check-versions.sh` (本リポジトリ同梱):

```bash
#!/usr/bin/env bash
set -euo pipefail
echo "==== versions ===="
aws --version
terraform version | head -1
kubectl version --client | head -2
helm version --short
cilium version --client
echo "==== AWS identity ===="
aws sts get-caller-identity
```

```bash
chmod +x scripts/check-versions.sh
./scripts/check-versions.sh
```

### 7. **AWS 料金注意** (このトラック全体に効く)

> **重要:** Track B は 1 章進めるたびに **EC2 / EBS / EIP** が立ち上がります。
> - t3.medium × 3 ≒ **$0.125/h** ≒ **$3 / 24h**
> - gp3 30 GB × 3 ≒ **$2.7 / 月** (起動有無に関わらず課金)
> - EIP は **EC2 に未アタッチだと課金される** (アタッチ中は無料)
>
> **章をまたぐ時は EC2 を `stop` する** か、寝る前は **`terraform destroy`**。
> 最後の [`99-cleanup`](../99-cleanup/) を必ず実行してください。

## やってみて気づくこと

- **入口** (IAM) と **出口** (タグ + Billing) を先に締めるのが、AWS で寝坊しないコツ
- AWS リソースは "見えないところで増殖する"。**タグが無いリソースは存在しないリソース** くらいのつもりで
- 学習用でも `~/.aws/credentials` の扱いは本番と同じ。MFA / SSO / gitleaks の 3 点セットが標準装備
- "リージョン" は思っているより越境しがち (`us-east-1` でしか作れない物がある、ACM は CloudFront 用は us-east-1 必須 etc)

## 参考
- AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
- IAM ベストプラクティス: https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html
- Billing アラート: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/monitor_estimated_charges_with_cloudwatch.html
- Resource Groups Tagging API: https://docs.aws.amazon.com/resourcegroupstagging/latest/APIReference/Welcome.html
- Terraform AWS Provider: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
