# 04 — EKS Pod Identity (IRSA からの移行)

## ゴール
- 旧来の **IRSA** (OIDC + ServiceAccount annotation + Trust Policy) を 1 度組んで痛みを再確認
- **EKS Pod Identity** (Pod Identity Agent + Association) で **Trust Policy ゼロ** で IAM を取れることを体感
- IRSA と Pod Identity が **共存** した場合の優先順位を確認
- Pod 内から `aws sts get-caller-identity` で **Role を assume している事実** を覗き見

---

## 🤔 なぜ必要？ (ストーリー)

> IRSA 時代の地獄:
> 1. cluster の **OIDC provider URL** を IAM に Identity Provider 登録
> 2. その thumbprint を取り、IAM Role の **Trust Policy** に書き込む
> 3. Trust Policy の `Condition` の `sub` 文字列を `system:serviceaccount:<ns>:<sa>` に **完全一致** で書く (typo すると `AccessDenied` だけが返り、原因が分からない)
> 4. ServiceAccount に `eks.amazonaws.com/role-arn: arn:aws:iam::xxx:role/yyy` をアノテーション
> 5. Pod が `STS:AssumeRoleWithWebIdentity` を打って Credential を得る
> 6. namespace か sa 名を変えたら **Trust Policy も書き換える**
>
> Pod Identity (2023/11 GA) はこれを **API 1 つ** に置き換える:
> ```bash
> aws eks create-pod-identity-association \
>   --cluster-name bootcamp --namespace app --service-account my-app \
>   --role-arn arn:aws:iam::xxx:role/my-role
> ```
>
> - **Trust Policy 不要** (Role の Trust は `pods.eks.amazonaws.com` という固定 principal だけ)
> - **OIDC provider 設定不要**
> - **複数 cluster で同じ Role を使い回し** が容易 (Association は cluster 単位)
>
> 「**Pod Identity が IRSA の Trust Policy 地獄を消した**」がこの章のメッセージです。

## ✨ 面白いポイント (設計)

### 1. **Pod Identity Agent (DaemonSet) が AWS_CONTAINER_CREDENTIALS_FULL_URI を Inject**
> **痺れ所:** Agent が **kubelet と協調して Pod の env と /var/run のソケット** を生やし、AWS SDK が普通に `boto3.client(...)` を呼ぶだけで credential を引ける。
> アプリは IRSA / Pod Identity を **区別すらしない**。

### 2. **Role の Trust Policy は 1 行 (`pods.eks.amazonaws.com`)**
> **痺れ所:** 「どの cluster / どの namespace / どの SA に使わせるか」は **Trust ではなく Association** で表現。
> 同じ Role を 10 cluster に Association するだけ。

### 3. **Cross-Account / Federation**
> **痺れ所:** Workload が居る account とは別の account の Role を Association で指せる (Target Role + STS chain)。
> IRSA でやろうとすると Trust Policy が複雑化 → Pod Identity だと宣言だけ。

### 4. **Credential Provider Chain の優先**
Pod Identity > IRSA > EC2 IMDS。Pod に両方仕込んでも **Pod Identity が勝つ**。移行は「Association を入れる → annotation を外す」の順で **無停止**。

## 😱 あるある罠

- **Pod Identity Agent が居ない** → Pod の env に `AWS_CONTAINER_*` が刺さらず credential が引けない。01 章の addon 設定で `eks-pod-identity-agent` を入れる
- **Association を作っただけで Pod を再起動していない** → 既存 Pod は古い env のまま。`kubectl rollout restart` を忘れない
- **IAM Role の Trust Policy を IRSA のまま** にしておくと混乱の元。Pod Identity に寄せたら `Principal: { "Service": "pods.eks.amazonaws.com" }` に書き換え (sts:AssumeRole + sts:TagSession)
- **SDK の version が古い (boto3 < 1.34, aws-sdk-go < v1.50)** → Pod Identity provider 未対応で IRSA に fallback できず失敗
- **複数 Association が同じ SA に紐づく** → API レベルで弾かれる。1 SA = 1 Association

## やること

### 0. 準備

01 章で `eks-pod-identity-agent` addon が入っていることを確認:

```bash
kubectl -n kube-system get ds eks-pod-identity-agent
# DESIRED CURRENT READY が全 node 数と一致
```

### 1. 検証用 IAM Role (S3 ListBucket のみ)

```hcl
# terraform/podid.tf
resource "aws_iam_role" "app_s3" {
  name = "bootcamp-app-s3"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      # ★ Pod Identity の固定 Principal
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy" "app_s3" {
  role = aws_iam_role.app_s3.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:ListAllMyBuckets", "s3:GetBucketLocation"]
      Resource = "*"
    }]
  })
}

resource "aws_eks_pod_identity_association" "app_s3" {
  cluster_name    = module.eks.cluster_name
  namespace       = "demo-podid"
  service_account = "app"
  role_arn        = aws_iam_role.app_s3.arn
}
```

```bash
cd terraform && terraform apply
```

### 2. ServiceAccount と検証 Pod

```bash
kubectl create ns demo-podid
kubectl -n demo-podid create sa app    # ★ annotation は付けない! (IRSA と違う)
```

```yaml
# manifests/probe.yaml
apiVersion: v1
kind: Pod
metadata: { name: probe, namespace: demo-podid }
spec:
  serviceAccountName: app
  containers:
    - name: cli
      image: public.ecr.aws/aws-cli/aws-cli:2.17.0
      command: ["sh", "-c", "sleep 3600"]
```

```bash
kubectl apply -f manifests/probe.yaml
kubectl -n demo-podid exec -it probe -- aws sts get-caller-identity
# {
#   "Arn": "arn:aws:sts::xxxx:assumed-role/bootcamp-app-s3/eks-bootcamp-demo-podid-app-..."
# }
kubectl -n demo-podid exec -it probe -- aws s3 ls
```

→ **annotation も Trust Policy も書いていない** のに credential が降ってきている。

### 3. 何が起きているか覗き見

```bash
kubectl -n demo-podid exec probe -- env | grep AWS_
# AWS_CONTAINER_CREDENTIALS_FULL_URI=http://169.254.170.23/v1/credentials
# AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE=/var/run/secrets/pods.eks.amazonaws.com/serviceaccount/eks-pod-identity-token
# AWS_REGION=ap-northeast-1
```

これを SDK が自動で読み credential を取りに行く (= "container credentials provider").

### 4. (比較) IRSA 版を 1 度組んで痛みを再現

```hcl
# terraform/irsa.tf (見比べる用)
data "aws_iam_policy_document" "irsa_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:demo-irsa:app"]   # ★ typo すると延々 AccessDenied
    }
  }
}

resource "aws_iam_role" "irsa_app_s3" {
  name               = "bootcamp-irsa-app-s3"
  assume_role_policy = data.aws_iam_policy_document.irsa_trust.json
}
```

```bash
kubectl create ns demo-irsa
kubectl -n demo-irsa create sa app
kubectl -n demo-irsa annotate sa app eks.amazonaws.com/role-arn=$(terraform output -raw irsa_role_arn)
```

→ Trust Policy の `sub` の typo / namespace 変更で **延々と AccessDenied** に苦しめられる古典体験ができる。

### 5. 移行 (IRSA → Pod Identity を無停止で)

1. Pod Identity Association を作る (priority が高い)
2. `kubectl rollout restart` で Pod を再起動 (env を更新)
3. IRSA annotation を外す:
   ```bash
   kubectl -n demo-irsa annotate sa app eks.amazonaws.com/role-arn-
   ```
4. SDK は **何の変更も無く** Pod Identity 経由に切り替わる

### 6. 後片付け

```bash
kubectl delete ns demo-podid demo-irsa
# Terraform 側で Association と Role を消すなら:
# terraform destroy -target=aws_eks_pod_identity_association.app_s3 ...
```

## やってみて気づくこと

- IRSA 時代の "OIDC URL / Thumbprint / Trust Policy sub" の **三点セットが消える** 解放感
- アプリ側コードは **1 文字も変えていない** (SDK の Provider Chain が吸収)
- Association は API なので、**新規 SA を作る → 即 Association** が IaC で素直に書ける
- `aws sts get-caller-identity` の `assumed-role/.../<session-name>` の session 名に **Pod 名や namespace** が入っていて追跡しやすい

## 参考

- EKS Pod Identity: https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html
- IRSA 比較: https://aws.amazon.com/blogs/containers/amazon-eks-pod-identity-a-new-way-for-applications-on-eks-to-obtain-iam-credentials/
- terraform-aws-modules/eks-pod-identity: https://github.com/terraform-aws-modules/terraform-aws-eks-pod-identity
- Credential Provider Chain 優先度: https://docs.aws.amazon.com/sdkref/latest/guide/standardized-credentials.html
