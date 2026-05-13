# 07 — Supply Chain on EKS (cosign + Kyverno)

## ゴール
- **ECR private repo** を Terraform で作成 (image scanning on push)
- GitHub Actions の **OIDC** で AWS にログイン → build → push → **cosign keyless sign**
- **Kyverno** を install し、`verifyImages` policy で **未署名 image の admission を拒否**
- **SBOM** (`cosign attach sbom`) と **SLSA provenance** の attest を体験
- (発展) ECR の image scan 結果を取得し、Critical があれば admission を拒否

---

## 🤔 なぜ必要？ (ストーリー)

> ある日、`docker.io/popular-app:latest` の image が **マルウェアに置き換わっていた**。
> 自社で build した image を `docker push` する時、誰でも push できる構成だったらどうする?
>
> サプライチェーン攻撃の現実的な対策は 3 段:
> 1. **誰が** その image を作ったかを **暗号学的に証明** (= cosign sign)
> 2. **何が** 入っているかを記録 (= SBOM)
> 3. cluster は **検証に通った image しか受け入れない** (= Kyverno verifyImages)
>
> EKS では ECR + GitHub Actions OIDC + Kyverno の **3 連結** で、追加コスト ~0 で実現できる。
> 「**Pod が起動する前に Admission が image を拒否する**」体験はここで一度はやっておくべき。

## ✨ 面白いポイント (設計)

### 1. **cosign keyless (OIDC 連携)**
> **痺れ所:** 秘密鍵を作らない。GitHub Actions の OIDC トークン → Sigstore Fulcio が **その場限りの証明書** を発行 → 署名 → 証明書も transparency log (Rekor) に公開。
> 「鍵を失くす / 漏らす」リスク自体が消える。

### 2. **GitHub Actions → AWS IAM OIDC**
> **痺れ所:** Actions の OIDC を IAM の Identity Provider に登録すれば、long-lived な AWS Access Key を **1 枚も保管しない**。
> リポジトリ条件 (`repo:owner/name:ref:refs/heads/main`) で AssumeRole 制限可能。

### 3. **Kyverno verifyImages = Admission 段で署名検証**
> **痺れ所:** ImagePullPolicy より前、**Pod が schedule される前** に admission webhook が `cosign verify` 相当を走らせる。
> 未署名 image は **Pod すら作れない**。

### 4. **SBOM と Provenance は "添付物"**
> **痺れ所:** image digest に対し、SBOM / Provenance / 脆弱性スキャン結果を **後から attach** できる。
> 「sign された image に、追加で attest が付く」という分離設計が美しい。

## 😱 あるある罠

- **`cosign verify` が `--certificate-identity-regexp` の typo で常に通る**: 文字列マッチなので **`.*` に近い regex は危険**
- **`pull-secrets` 経由で別レジストリの image を引いている**: verifyImages の `imageReferences` で **対象外** だと素通り
- **policy を `audit` にしたまま `enforce` に上げ忘れ**: 監視はしているのに **何も拒否されていない**
- **Kyverno admission webhook の failurePolicy=Fail で webhook 自身が落ちる** → クラスタが Pod 一切作れなくなる。 **kube-system は exception** に
- **GHA OIDC の `permissions: id-token: write` を忘れる** → token が無くて AssumeRoleWithWebIdentity が失敗
- **Rekor / Fulcio の URL を private 化していない** → 商用厳格運用では Sigstore の private deploy が必要

## やること

### 0. 準備

01〜06 章の EKS と Argo CD が動いている前提。
GitHub Actions が使える repo を 1 つ用意 (この bootcamp 用の fork が分かりやすい)。

### 1. Terraform: ECR + GitHub OIDC AssumeRole

```hcl
# terraform/ecr.tf
resource "aws_ecr_repository" "hello" {
  name                 = "k8s-bootcamp/hello"
  image_tag_mutability = "IMMUTABLE"          # ★ tag 上書き禁止
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" }
}

# GitHub Actions OIDC -> AWS IAM
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "gha_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:<owner>/<repo>:ref:refs/heads/main"]  # ★ ここで repo 縛り
    }
  }
}

resource "aws_iam_role" "gha_ecr" {
  name               = "gha-ecr-push"
  assume_role_policy = data.aws_iam_policy_document.gha_trust.json
}

resource "aws_iam_role_policy_attachment" "gha_ecr" {
  role       = aws_iam_role.gha_ecr.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

output "ecr_url"      { value = aws_ecr_repository.hello.repository_url }
output "gha_role_arn" { value = aws_iam_role.gha_ecr.arn }
```

```bash
cd terraform && terraform apply
```

### 2. GitHub Actions workflow

[`.github/workflows/build-sign.yaml`](./workflows/build-sign.yaml):

```yaml
name: build-sign-push
on:
  push: { branches: [main] }

permissions:
  id-token: write          # ★ OIDC
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    env:
      ECR: <acct>.dkr.ecr.ap-northeast-1.amazonaws.com/k8s-bootcamp/hello
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::<acct>:role/gha-ecr-push
          aws-region: ap-northeast-1

      - uses: aws-actions/amazon-ecr-login@v2

      - name: Build & push
        run: |
          IMG="${{ env.ECR }}:${{ github.sha }}"
          docker build -t "$IMG" .
          docker push "$IMG"
          echo "IMG=$IMG" >> $GITHUB_ENV

      - uses: sigstore/cosign-installer@v3
        with: { cosign-release: 'v2.4.1' }

      - name: Cosign sign (keyless via GH OIDC)
        env: { COSIGN_EXPERIMENTAL: "1" }
        run: |
          DIGEST=$(crane digest "${{ env.IMG }}")
          cosign sign --yes "${{ env.ECR }}@$DIGEST"

      - name: Generate & attach SBOM (syft)
        run: |
          curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin
          syft "${{ env.IMG }}" -o spdx-json > sbom.spdx.json
          cosign attest --yes --predicate sbom.spdx.json --type spdxjson "${{ env.ECR }}@$(crane digest ${{ env.IMG }})"
```

### 3. Kyverno を install

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm upgrade --install kyverno kyverno/kyverno \
  --namespace kyverno --create-namespace \
  --version 3.2.6 \
  --set admissionController.replicas=3 \
  --wait
kubectl -n kyverno get pods
```

### 4. verifyImages policy (cosign 署名検証)

[`manifests/verify-images.yaml`](./manifests/verify-images.yaml):

```yaml
apiVersion: kyverno.io/v2beta1
kind: ClusterPolicy
metadata: { name: verify-ecr-signed }
spec:
  validationFailureAction: Enforce         # 最初は Audit で慣らす
  webhookTimeoutSeconds: 30
  failurePolicy: Fail
  rules:
    - name: verify-cosign-keyless
      match:
        any:
          - resources:
              kinds: [Pod]
              namespaces: ["app-*", "default"]   # ★ 対象 ns を絞る (kube-system 除外)
      verifyImages:
        - imageReferences:
            - "<acct>.dkr.ecr.ap-northeast-1.amazonaws.com/k8s-bootcamp/*"
          attestors:
            - entries:
                - keyless:
                    issuer: "https://token.actions.githubusercontent.com"
                    subject: "https://github.com/<owner>/<repo>/.github/workflows/build-sign.yaml@refs/heads/main"
                    rekor: { url: "https://rekor.sigstore.dev" }
          required: true
          mutateDigest: true     # tag を digest に置換 (重要)
```

```bash
kubectl apply -f manifests/verify-images.yaml
```

### 5. テスト: 未署名 / 署名済みの両方を試す

```bash
# 未署名 (失敗するはず)
kubectl run bad --image=nginx:1.27 -n default
# → Error from server: admission webhook "mutate.kyverno.svc" denied the request:
#    no matching signatures (verify-cosign-keyless)

# 署名済み ECR image (通るはず)
kubectl run good --image=<acct>.dkr.ecr.ap-northeast-1.amazonaws.com/k8s-bootcamp/hello:abc1234 -n default
# → pod/good created
```

### 6. (発展) SBOM の検証

```bash
cosign verify-attestation --type spdxjson \
  --certificate-identity-regexp '^https://github.com/<owner>/<repo>' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  <acct>.dkr.ecr.../k8s-bootcamp/hello@sha256:...
```

Kyverno でも `verifyImages.attestations` で SBOM 必須化が可能。

### 7. (発展) ECR scan の Critical を Kyverno で参照

```yaml
# ECR の脆弱性 finding を Kyverno の `imageVerifyPolicy.required: false + image.failurePolicy` で柔軟運用
# 厳格にやるなら API でスキャン結果を取り、`required: ALL` の attestation として cosign attach
```

### 8. 後片付け

```bash
kubectl delete -f manifests/verify-images.yaml
helm -n kyverno uninstall kyverno
kubectl delete ns kyverno
# ECR repo / Role は terraform destroy で
```

## やってみて気づくこと

- 「未署名は **Pod すら作れない**」の防壁は、運用始まると **驚くほど効く**
- keyless 署名は **鍵管理ゼロ** で初日から運用に乗る (private Sigstore 化は後でも)
- `validationFailureAction: Audit` でしばらく回し、**何が落ちるかを観察してから Enforce** が安全
- SBOM が image digest に紐づくので、後で CVE 出た時に「**この digest を使う Pod は誰?**」が逆引きできる
- `mutateDigest: true` で tag → digest に書換するので、**`latest` の固定化** も同時に実現する

## 参考

- Sigstore / cosign: https://docs.sigstore.dev/
- Kyverno verifyImages: https://kyverno.io/docs/writing-policies/verify-images/
- GitHub Actions OIDC: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect
- AWS Signer (代替): https://docs.aws.amazon.com/signer/latest/developerguide/Welcome.html
- SLSA provenance: https://slsa.dev/
