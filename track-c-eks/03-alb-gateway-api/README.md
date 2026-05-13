# 03 — AWS Load Balancer Controller + Gateway API

## ゴール
- **AWS Load Balancer Controller v2.8+** を Pod Identity で install
- Gateway API の **CRD** を導入し、`GatewayClass` (controller `gateway.k8s.aws/alb`) を有効化
- `Gateway` + `HTTPRoute` で **ALB が自動生成** されることを目視
- **ACM 証明書 + HTTPS リスナ** を自動アタッチ
- (発展) HTTPRoute の `weight` で **トラフィック分割** カナリア

---

## 🤔 なぜ必要？ (ストーリー)

> EKS でアプリを世に出す時、伝統的には **Ingress + 大量のアノテーション** だった:
> `alb.ingress.kubernetes.io/scheme: internet-facing`
> `alb.ingress.kubernetes.io/target-type: ip`
> `alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'`
> `alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:...`
> `alb.ingress.kubernetes.io/actions.weighted-target: '{...JSON...}'`
> ...
>
> Ingress リソースの **9 割がアノテーション** という現実。設定が文字列なので型エラーも出ない。
>
> Gateway API はこれを **YAML の構造化された属性** に置き換える。
> AWS LB Controller v2.8 で **Gateway API がプロダクションサポート** になり、もはや Ingress を書く理由は無い。
> 「**ALB Controller の Gateway API 対応で、Ingress アノテーション地獄を捨てる**」のがこの章です。

## ✨ 面白いポイント (設計)

### 1. **責務の三層分離 (`GatewayClass` / `Gateway` / `HTTPRoute`)**
> **痺れ所:** インフラ管理者は `GatewayClass`、プラットフォーム team は `Gateway` (= ALB)、アプリ team は `HTTPRoute` (= ルーティング) を所有。
> Ingress 時代の「全部 1 個の YAML に詰め込み」が **役割で割れる**。

### 2. **複数 HTTPRoute で 1 つの ALB を共有**
> **痺れ所:** namespace A と B が **同じ ALB** にぶら下がる構成が、Ingress 時代より素直に書ける。
> ALB を namespace ごとに増やしてコスト爆発する事故が減る。

### 3. **`backendRefs[].weight` でカナリア**
> **痺れ所:** ALB 自身が **重み付き forward** をネイティブサポート。Argo Rollouts などが Step を変えるだけで progressive delivery。

### 4. **ACM 証明書の自動検出**
> **痺れ所:** `Listener.tls.certificateRefs` に **書かない** で済むパターンも。ALB Controller が **SNI ドメイン名でマッチする ACM 証明書を自動添付**。

## 😱 あるある罠

- **Public subnet の tag `kubernetes.io/role/elb=1` が無い** → ALB が subnet を見つけられず Pending
- **target-type が `instance` のまま (デフォルト)** → Karpenter Node 上の Pod に NodePort が必要。`ip` を指定して直接 Pod IP を pool に
- **VPC CNI の `WARM_IP_TARGET` が足りない** → Pod IP が回らず ALB が Healthy にならない
- **HTTPRoute の `parentRefs.namespace` 不整合** → Gateway 側で `allowedRoutes.namespaces.from: Same` を指定したら別 ns からは繋がらない
- **`gateway.networking.k8s.io` CRD を入れ忘れ** → ALB Controller が静かに何もしない
- **Controller の version が古い (v2.7 以下)** → Gateway API がそもそも未対応

## やること

### 0. 準備

01 章の EKS + 02 章の Karpenter が動いていること。
ALB Controller 用の IAM Policy と Pod Identity Association を作る。

### 1. Terraform: ALB Controller の IAM

```hcl
# terraform/lbc.tf
data "http" "lbc_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.8.0/docs/install/iam_policy.json"
}

resource "aws_iam_policy" "lbc" {
  name   = "AWSLoadBalancerControllerIAMPolicy"
  policy = data.http.lbc_policy.response_body
}

module "lbc_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4"

  name                  = "aws-load-balancer-controller"
  attach_custom_policy  = true
  additional_policy_arns = { lbc = aws_iam_policy.lbc.arn }

  associations = {
    main = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }
}
```

```bash
cd terraform && terraform apply
```

### 2. Gateway API CRD を入れる

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml
kubectl get crd | grep gateway.networking.k8s.io
# httproutes / gateways / gatewayclasses / referencegrants が居る
```

### 3. AWS Load Balancer Controller を helm install

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --version 1.8.2 \
  --set clusterName=bootcamp \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set enableServiceMutatorWebhook=false \
  --set defaultTags.Project=k8s-bootcamp \
  --set defaultTags.Track=C \
  --wait

kubectl -n kube-system get pods -l app.kubernetes.io/name=aws-load-balancer-controller
```

> Pod Identity を使うので `serviceAccount.annotations.eks.amazonaws.com/role-arn` は **不要**。

### 4. GatewayClass を作る

[`manifests/gatewayclass-alb.yaml`](./manifests/gatewayclass-alb.yaml):

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: aws-alb
spec:
  controllerName: gateway.k8s.aws/alb
```

```bash
kubectl apply -f manifests/gatewayclass-alb.yaml
kubectl get gatewayclass aws-alb
# Accepted: True
```

### 5. デモアプリ + Gateway + HTTPRoute

[`manifests/demo.yaml`](./manifests/demo.yaml):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: hello, namespace: default }
spec:
  replicas: 2
  selector: { matchLabels: { app: hello } }
  template:
    metadata: { labels: { app: hello } }
    spec:
      containers:
        - name: hello
          image: hashicorp/http-echo:1.0.0
          args: ["-text=hello from EKS Gateway API", "-listen=:8080"]
          ports: [{ containerPort: 8080 }]
---
apiVersion: v1
kind: Service
metadata: { name: hello, namespace: default }
spec:
  selector: { app: hello }
  ports: [{ port: 80, targetPort: 8080 }]
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: public
  namespace: default
  annotations:
    alb.gateway.kubernetes.io/scheme: internet-facing
    alb.gateway.kubernetes.io/target-type: ip      # ★ Pod IP を直接 ALB target に
    alb.gateway.kubernetes.io/load-balancer-attributes: |
      idle_timeout.timeout_seconds=60
spec:
  gatewayClassName: aws-alb
  listeners:
    - name: http
      port: 80
      protocol: HTTP
      allowedRoutes: { namespaces: { from: Same } }
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: hello, namespace: default }
spec:
  parentRefs:
    - name: public
  hostnames: ["hello.example.com"]
  rules:
    - matches: [{ path: { type: PathPrefix, value: "/" } }]
      backendRefs:
        - name: hello
          port: 80
```

```bash
kubectl apply -f manifests/demo.yaml
kubectl get gateway public -w     # ADDRESS に ALB の DNS が入るのを待つ (1〜2 分)
```

```bash
ALB=$(kubectl get gateway public -o jsonpath='{.status.addresses[0].value}')
curl -H 'Host: hello.example.com' http://$ALB/
# → "hello from EKS Gateway API"
```

### 6. HTTPS + ACM 証明書 (本番に近づける)

事前に Route53 で `example.com` の hosted zone を持ち、ACM 証明書 (`*.example.com`) を発行しておく。

```yaml
# Gateway listener に HTTPS を追加
listeners:
  - name: https
    port: 443
    protocol: HTTPS
    tls:
      mode: Terminate
      certificateRefs:
        - kind: Secret    # ACM の場合は controller がドメインから自動検出
          name: tls-cert  # ダミーで OK。実態は ACM
    allowedRoutes: { namespaces: { from: Same } }
```

または ALB Controller の **アノテーション経由** で ACM を直指定:

```yaml
metadata:
  annotations:
    alb.gateway.kubernetes.io/certificate-arn: "arn:aws:acm:ap-northeast-1:xxxx:certificate/yyyy"
```

### 7. (発展) HTTPRoute の重み付きで Canary

```yaml
rules:
  - backendRefs:
      - { name: hello-v1, port: 80, weight: 90 }
      - { name: hello-v2, port: 80, weight: 10 }
```

ALB の `forward` action がそのまま 90:10 を反映する。Argo Rollouts と組み合わせれば自動 Step Up。

### 8. 後片付け

```bash
kubectl delete -f manifests/demo.yaml         # ★ Gateway を消すと ALB が delete される
kubectl delete -f manifests/gatewayclass-alb.yaml
# Controller 自体は残してもコストは Pod 程度
```

> **重要:** Gateway を消し忘れて namespace を delete すると、稀に finalizer が残って **ALB だけが孤児** に。
> 99-cleanup で `aws elbv2 describe-load-balancers` を必ず実行。

## やってみて気づくこと

- Ingress の長大アノテーションが **listener / route / backendRef の 3 概念に綺麗に分解** される
- 1 つの ALB を複数 namespace の HTTPRoute が共有でき、コストが線形に増えない
- target-type=ip にすると ALB target が **Pod IP** になり、Karpenter で Node が出入りしても再登録不要
- ALB の作成は ~90 秒、scale 変更は数秒。Controller の reconcile log が出る

## 参考

- AWS Load Balancer Controller: https://kubernetes-sigs.github.io/aws-load-balancer-controller/
- Gateway API on ALB: https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/gateway/gateway-api/
- Gateway API spec: https://gateway-api.sigs.k8s.io/
- ACM 自動検出: https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.8/guide/ingress/cert_discovery/
