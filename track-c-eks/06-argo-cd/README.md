# 06 — Argo CD で GitOps

## ゴール
- **Argo CD** を helm で install、ALB (Gateway API) 越しに UI 公開
- **App-of-Apps** で「クラスタを構成する全アドオン」を 1 つの Application から bootstrapping
- **ApplicationSet** で multi-tenant / multi-cluster の自動生成パターン
- **Sync Wave** で `CRD → Operator → Workload` の順序を強制
- (発展) **Argo CD Image Updater** で ECR の新タグを自動 PR / 自動 sync

---

## 🤔 なぜ必要？ (ストーリー)

> Track 0〜05 では `kubectl apply` を直接打ってきた。テストには良いが本番では:
> - 「あのマニフェスト、いつ誰が apply したっけ?」
> - 「helm の `--values` が手元と本番でズレてる」
> - 「`kubectl edit` で直接書き換えた deployment が IaC と乖離」
>
> **GitOps** はこれを 1 行で解決する: **「クラスタの状態は Git の `HEAD` と等しい」**。
> 差分があれば Argo CD が **勝手に戻す** (= self-healing)。
>
> 「**GitOps なら kubectl apply で本番がズレる不安が消える**」のがこの章の体験です。

## ✨ 面白いポイント (設計)

### 1. **App-of-Apps パターン**
> **痺れ所:** ルート Application が **子 Application を 10 個生む**。クラスタの全構成 (LB Controller / Karpenter / Kyverno / 監視 / アプリ) が **1 個の Git ツリー** に。
> 新クラスタは「ルート Application を 1 個作るだけ」で立ち上がる。

### 2. **ApplicationSet で N 個の Application を自動生成**
> **痺れ所:** `generators: clusters` で **登録クラスタの数だけ** Application を自動増殖。
> dev / stg / prd を CRD の Cartesian product でテンプレ展開 → multi-cluster GitOps が **書くべき YAML が線形** に。

### 3. **Sync Wave で順序保証**
> **痺れ所:** Application / resource に `argocd.argoproj.io/sync-wave: "-1"` のようなアノテーションを付け、**小さい数字から sync**。
> 「CRD が無いのに CR を apply」事故が消える。

### 4. **Self-Heal & Auto-Prune**
> **痺れ所:** `syncPolicy.automated: { prune: true, selfHeal: true }` で、Git に無いものは消す + 手動書換は即戻す。
> "**本番が Git と一致していること**" が物理法則レベルで保証される。

### 5. **Argo CD 自身を Argo CD で管理 (self-management)**
> **痺れ所:** 最初の `helm install` のあとは、Argo CD 自身も Application 化。**Argo CD の helm values 変更が PR レビュー対象** になる完成形。

## 😱 あるある罠

- **`syncPolicy.automated.prune` を本番で迂闊に on**: Git から消すと **即削除**。最初は手動 sync で慣らす
- **CRD と CR の sync 順を Sync Wave で固定し忘れ** → `no matches for kind` で sync 失敗
- **`Application` の `destination.server` を `https://kubernetes.default.svc` 以外に指定** → クラスタ未登録で sync 失敗
- **ApplicationSet の generator 設定ミス** で `kubectl get applications` が **1000 個** 生まれる
- **Argo CD UI を素朴に LoadBalancer Service で晒す** → 公開 ALB で admin/password が攻撃対象に。**OIDC + Cognito or GitHub** を入れる

## やること

### 0. 準備

01〜05 章の cluster が動いていること。ALB Controller + Gateway API が居ること。
Git リポジトリ (このリポジトリの fork でも、自分の手元の private repo でも可) を用意。

### 1. Argo CD を helm install

```bash
kubectl create ns argocd
helm repo add argo https://argoproj.github.io/argo-helm

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --version 7.6.12 \
  --set 'configs.params.server\.insecure=true' \
  --set 'global.tolerations[0].operator=Exists' \
  --wait
kubectl -n argocd get pods
```

初期 admin パスワード:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

### 2. UI 公開 (Gateway API)

[`manifests/argocd-gateway.yaml`](./manifests/argocd-gateway.yaml):

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: argocd
  namespace: argocd
  annotations:
    alb.gateway.kubernetes.io/scheme: internet-facing
    alb.gateway.kubernetes.io/target-type: ip
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
metadata: { name: argocd, namespace: argocd }
spec:
  parentRefs: [{ name: argocd }]
  hostnames: ["argocd.example.com"]
  rules:
    - matches: [{ path: { type: PathPrefix, value: "/" } }]
      backendRefs: [{ name: argocd-server, port: 80 }]
```

```bash
kubectl apply -f manifests/argocd-gateway.yaml
kubectl -n argocd get gateway argocd -w
# ADDRESS に ALB DNS が入ったら ブラウザで http://<alb>/ → admin / <初期パスワード>
```

### 3. App-of-Apps の root Application

リポジトリ構成 (例):
```
gitops/
├── apps/
│   ├── root.yaml              ← Application of Applications
│   ├── karpenter.yaml
│   ├── aws-lb-controller.yaml
│   ├── kyverno.yaml
│   └── demo-hello.yaml
└── manifests/
    ├── karpenter/             ← NodePool 等
    ├── kyverno/               ← policy YAML
    └── demo-hello/            ← Deployment + Service + HTTPRoute
```

[`manifests/argocd-root.yaml`](./manifests/argocd-root.yaml):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
  finalizers: ["resources-finalizer.argocd.argoproj.io"]
spec:
  project: default
  source:
    repoURL: https://github.com/<you>/k8s-bootcamp-gitops.git
    targetRevision: main
    path: gitops/apps          # ← この dir の Application 群を全部 apply
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ApplyOutOfSyncOnly=true
```

```bash
kubectl apply -f manifests/argocd-root.yaml
kubectl -n argocd get applications -w
```

### 4. 子 Application の例 (Sync Wave 付き)

```yaml
# gitops/apps/karpenter.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: karpenter
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-10"   # ★ アドオンは早めに
spec:
  project: default
  source:
    repoURL: https://github.com/<you>/k8s-bootcamp-gitops.git
    path: gitops/manifests/karpenter
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: karpenter
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions: ["ServerSideApply=true"]
```

```yaml
# gitops/apps/demo-hello.yaml  (Sync Wave: 10 = アドオン後)
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "10"
```

### 5. ApplicationSet で N namespace に同じアプリを配る

[`manifests/applicationset-tenants.yaml`](./manifests/applicationset-tenants.yaml):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata: { name: tenants, namespace: argocd }
spec:
  generators:
    - list:
        elements:
          - { tenant: team-a, ns: app-a }
          - { tenant: team-b, ns: app-b }
          - { tenant: team-c, ns: app-c }
  template:
    metadata:
      name: 'hello-{{tenant}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/<you>/k8s-bootcamp-gitops.git
        path: gitops/manifests/demo-hello
        targetRevision: main
        helm:
          parameters:
            - { name: tenant, value: '{{tenant}}' }
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{ns}}'
      syncPolicy:
        automated: { prune: true, selfHeal: true }
        syncOptions: ["CreateNamespace=true"]
```

```bash
kubectl apply -f manifests/applicationset-tenants.yaml
kubectl -n argocd get applications | grep hello-
```

→ 3 個の Application が **自動生成** され、各 namespace に同じアプリが展開される。

### 6. (発展) Argo CD Image Updater で ECR の新 tag を自動反映

```bash
helm upgrade --install argocd-image-updater argo/argocd-image-updater \
  -n argocd \
  --set config.argocd.grpcWeb=true \
  --set config.argocd.serverAddress=argocd-server.argocd.svc.cluster.local \
  --set config.registries[0].name=ecr \
  --set config.registries[0].api_url='https://<acct>.dkr.ecr.ap-northeast-1.amazonaws.com' \
  --set config.registries[0].prefix='<acct>.dkr.ecr.ap-northeast-1.amazonaws.com' \
  --set config.registries[0].credentials='ext:/scripts/ecr-login.sh'
```

Application に annotation を付ければ、新タグ検出時に **Git に PR** (write-back: git) または直接 Argo CD で update (write-back: argocd):

```yaml
metadata:
  annotations:
    argocd-image-updater.argoproj.io/image-list: app=<acct>.dkr.ecr...../hello
    argocd-image-updater.argoproj.io/app.update-strategy: semver
    argocd-image-updater.argoproj.io/write-back-method: git
```

### 7. 後片付け

```bash
kubectl delete application root -n argocd      # ★ 子 Application も連鎖削除
kubectl delete -f manifests/argocd-gateway.yaml
helm -n argocd uninstall argocd
kubectl delete ns argocd
```

> 注意: 子 Application が管理しているリソース (Karpenter / LB Controller など) も全部消えるので順番を守る。

## やってみて気づくこと

- 1 個の **root Application** が `kubectl apply` の代わりになり、Git push = デプロイ になる感覚
- `kubectl edit deploy` で直接書き換えても **数秒で戻る** 不気味な自己治癒
- ApplicationSet の generator (list / clusters / git / matrix) で **テンプレ展開がコード化** される強さ
- Sync Wave のおかげで「CRD 入る前に CR を投げて失敗」が消える
- Argo CD UI のグラフが、Service → Endpoint → Pod まで **クリックで降りれる** ので障害 1 次切り分けが速い

## 参考

- Argo CD: https://argo-cd.readthedocs.io/
- App-of-Apps: https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/
- ApplicationSet: https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/
- Sync Waves: https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/
- Image Updater: https://argocd-image-updater.readthedocs.io/
