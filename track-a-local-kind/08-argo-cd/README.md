# 08 — GitOps with Argo CD

## ゴール
- **Argo CD** を kind に install し、UI と CLI を両方触る
- Git リポジトリのマニフェストを **`Application` CR** で同期する
- **sync wave** で apply 順序を制御する (CRD → CR の順など)
- **`ApplicationSet`** で複数 namespace / 複数 cluster へ宣言的に展開する
- **app-of-apps** パターンで「Argo CD 自体を GitOps 管理」する

---

## 🤔 なぜ必要？ (ストーリー)

> 上司:「先週 prod で apply した HPA、誰が当てた? Git に履歴ないんだけど」
> あなた:「あ、緊急対応で `kubectl apply` を直接…」
> → **Git が真実 (source of truth) から外れる** 瞬間。これが積み重なると、誰も再現できないクラスタが出来上がる。
>
> 別の日:「dev は v1.27、stg は v1.27.3、prod は v1.26 のままで何で差分があるか分かりません」
> → 3 つの環境に `kubectl apply` した順序と内容を覚えている人がいない。
>
> さらに:「ロールバックは前のマニフェストに戻して再 apply してください」
> → 「前のマニフェスト」がどこにも残っていない。
>
> 「**Git に書いてあるものが、クラスタの状態である**」と決めて、それ以外を禁じる ⇒ **GitOps**。
> Argo CD は **コミット ⇄ クラスタ状態** を双方向に比較し、差分を **UI で見せて自動修正する**。

```
従来 (CIOps)  : Git → CI が kubectl apply → クラスタ。「Git を反映する保証」が CI のロジック頼み
GitOps        : Git → Argo CD が常に reconcile → クラスタ。「ずれたら警告 or 自動修復」
```

## ✨ 面白いポイント (設計)

### 1. **`Application` CR が "デプロイの宣言"**

```yaml
spec:
  source:
    repoURL: https://github.com/me/myapp
    targetRevision: main
    path: manifests/prod
  destination:
    server: https://kubernetes.default.svc
    namespace: app
  syncPolicy:
    automated: {prune: true, selfHeal: true}
```

> **痺れ所:** デプロイ手順が **YAML 1 枚**。CI スクリプトに書く代わりに、Git に置いた `Application` を Argo CD が拾うだけ。`Application` 自体も Git で管理 (= app-of-apps)。

### 2. **差分を UI で見る**

`kubectl diff` でしか分からなかった「クラスタの今 vs Git の理想」が、Web UI で **resource 単位の色付き diff** で見える。

> **痺れ所:** 「**差分を眺める** という体験」を初めて味わうと、後戻りできない。レビューが楽しくなる。

### 3. **sync wave で順序保証**

CRD を入れる前に CR を apply して `no matches for kind` で死ぬ事故、誰しもある。Argo CD は annotation 1 つで:

```yaml
metadata:
  annotations:
    argocd.argo.cn/sync-wave: "-1"   # 先に
```

数字が小さいものから順に apply。`-1` で CRD、`0` で CR、`1` で Deployment、と段階を分けられる。

### 4. **`ApplicationSet` = "Application のジェネレータ"**

```yaml
generators:
  - list:
      elements:
        - {cluster: dev,  url: https://dev.example.com}
        - {cluster: stg,  url: https://stg.example.com}
        - {cluster: prod, url: https://prod.example.com}
```

template に `{{cluster}}` を挿し込んで、**3 つの `Application` を自動生成**。クラスタを足すたびに 1 行追加するだけ。

### 5. **`selfHeal` と `prune`**

- `selfHeal: true` — 誰かが `kubectl edit` で書き換えても **Git 通りに戻す**
- `prune: true` — Git から消したら **クラスタからも消す**

「直接いじる」を物理的に潰せる。

## 😱 あるある罠

- **`server.insecure=true` を本番で**: TLS なしの HTTP UI になる。ローカルだけ
- **`prune: true` を初日から本番に**: Argo CD が "Git に無いから消す" と判断して既存 Service を全削除、なんて事故。最初は `prune: false` で観察
- **CRD と CR を同じ wave に**: `Required value: ...crd not found`。CRD は `sync-wave: -1` などで先に
- **`Application` の `source.path` が typo**: status が `Unknown` のまま何も起きない → status / events を見る癖
- **`automated` を OFF にしたまま運用**: せっかくの GitOps が「Sync ボタンを人が押す業務」になる
- **`apiserver` が `kubernetes.default.svc` で in-cluster 接続**: ローカルクラスタは OK。マルチクラスタ運用時は `argocd cluster add` で別 context を登録

## やること

### 0. 準備

```bash
kubectl create ns argocd
kubectl label ns argocd pod-security.kubernetes.io/enforce=baseline --overwrite
```

### 1. Argo CD を入れる

```bash
ARGOCD_VER=v2.13.1
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VER}/manifests/install.yaml
kubectl -n argocd wait --for=condition=Available deploy --all --timeout=240s
```

**UI を見る:**

```bash
# ローカル限定: 平文 HTTP モード
kubectl -n argocd patch cm argocd-cmd-params-cm \
  --type merge -p '{"data":{"server.insecure":"true"}}'
kubectl -n argocd rollout restart deploy argocd-server

# 初期パスワード (admin)
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo

# port-forward
kubectl -n argocd port-forward svc/argocd-server 8080:80 &
# → http://localhost:8080  (admin / 上のパスワード)
```

**CLI も入れる:**

```bash
# Mac:    brew install argocd
# Linux:  curl -sSL -o /usr/local/bin/argocd \
#           https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VER}/argocd-linux-amd64 \
#         && chmod +x /usr/local/bin/argocd
argocd login localhost:8080 --username admin \
  --password "$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)" \
  --insecure
```

### 2. はじめての `Application` — public sample を sync

Argo CD の公式サンプル `guestbook` を直接同期してみる:

```bash
kubectl create ns guestbook
kubectl label ns guestbook pod-security.kubernetes.io/enforce=baseline --overwrite
```

```yaml
# app-guestbook.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps
    targetRevision: HEAD
    path: guestbook
  destination:
    server: https://kubernetes.default.svc
    namespace: guestbook
  syncPolicy:
    automated:
      prune: false       # 最初は安全に
      selfHeal: false
    syncOptions:
      - CreateNamespace=false  # 既に作ってあるので
```

```bash
kubectl apply -f app-guestbook.yaml
argocd app sync guestbook
argocd app get guestbook
# Health: Healthy / Sync: Synced
kubectl -n guestbook get all
```

UI を開くと **resource tree** が描かれている。試しに `kubectl -n guestbook scale deploy/guestbook-ui --replicas=3` してみると、UI で **OutOfSync** がリアルタイムに見える。

### 3. `selfHeal` を体感

`Application` を編集して `selfHeal: true` に:

```bash
kubectl -n argocd patch application guestbook --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"prune":false,"selfHeal":true}}}}'

# 手で壊す
kubectl -n guestbook scale deploy/guestbook-ui --replicas=5
# 数秒待つと…
kubectl -n guestbook get deploy guestbook-ui
# replicas が Git 通りに戻る (1)
```

> **痺れ所:** Git に書いていない変更は **無かったことになる**。スナップショット型の運用文化が出来上がる。

### 4. sync wave を試す

CRD と CR の順番が問題になる典型例を、手元のリソースで再現:

```yaml
# manifests-wave/00-cm.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: stage-1
  namespace: guestbook
  annotations: {argocd.argo.cn/sync-wave: "-1"}
data: {hello: "first"}
---
# manifests-wave/10-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: read-cm
  namespace: guestbook
  annotations: {argocd.argo.cn/sync-wave: "1"}
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: r
          image: busybox:1.36
          command: ["sh","-c","cat /etc/cm/hello"]
          volumeMounts: [{name: cm, mountPath: /etc/cm}]
      volumes:
        - name: cm
          configMap: {name: stage-1}
```

これを git repo に push、または `app-of-apps` 用に **本リポジトリの fork** を指して `Application` を作る。`-1` の ConfigMap が先、`1` の Job が後。

### 5. app-of-apps パターン

「`Application` を管理する `Application`」。これによって Argo CD 自身も Git に書いた変更で更新できる。

```
repo/
├── apps/                       ← Application 群を置く
│   ├── root.yaml               ← これだけ手で apply
│   ├── guestbook.yaml
│   └── kyverno.yaml
└── manifests/
    └── ...
```

```yaml
# apps/root.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<you>/k8s-bootcamp
    targetRevision: main
    path: track-a-local-kind/08-argo-cd/apps
    directory: {recurse: true}
  destination: {server: https://kubernetes.default.svc, namespace: argocd}
  syncPolicy:
    automated: {prune: true, selfHeal: true}
```

```bash
# 最初の 1 回だけ:
kubectl apply -f apps/root.yaml
```

これ以降、`apps/` 配下に `Application` を追加 → コミット → 自動で展開。

### 6. `ApplicationSet` で 3 namespace へ同じアプリを展開

```yaml
# appset-multi-ns.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: hello-multi
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - {env: dev}
          - {env: stg}
          - {env: prod}
  template:
    metadata:
      name: 'hello-{{env}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/argoproj/argocd-example-apps
        targetRevision: HEAD
        path: guestbook
      destination:
        server: https://kubernetes.default.svc
        namespace: 'hello-{{env}}'
      syncPolicy:
        automated: {prune: true, selfHeal: true}
        syncOptions: [CreateNamespace=true]
```

```bash
kubectl apply -f appset-multi-ns.yaml
kubectl -n argocd get applications
# hello-dev / hello-stg / hello-prod が生成されている

kubectl get ns | grep hello-
# hello-dev / hello-stg / hello-prod
```

`list` 以外に **Git directory generator** / **cluster generator** / **matrix generator** がある。「クラスタが増えたら 1 行足すだけ」の世界。

### 7. 後片付け

```bash
kubectl delete -f appset-multi-ns.yaml --ignore-not-found
kubectl delete -f app-guestbook.yaml --ignore-not-found
kubectl delete ns hello-dev hello-stg hello-prod guestbook --ignore-not-found
kubectl delete ns argocd
```

## やってみて気づくこと

- 「Git にコミット → 数秒後に UI に反映 → クラスタにも反映」のフィードバックループが **異常に気持ち良い**
- `selfHeal` を ON にすると、**`kubectl edit` を打つ手が止まる** (= 直しても戻されるから)
- sync wave を覚えると CRD の install 順問題が **annotation 1 行で解決**
- `ApplicationSet` で「環境を増やす = list に 1 行追加」になり、Terraform でも届かない**運用の宣言性**が手に入る
- UI の resource tree が**チーム内の共通言語**になる: 「あの赤いノードを sync して」だけで会話が成立

## 参考

- Argo CD: https://argo-cd.readthedocs.io/
- ApplicationSet: https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/
- Sync waves & hooks: https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/
- App-of-apps: https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/
- OpenGitOps principles: https://opengitops.dev/
- 例: argocd-example-apps: https://github.com/argoproj/argocd-example-apps
