# 05 — ValidatingAdmissionPolicy (CEL)

## ゴール
- **ValidatingAdmissionPolicy (VAP)** + **CEL** で、Webhook サーバを書かずにアドミッション制御を入れる
- `ValidatingAdmissionPolicy` と `ValidatingAdmissionPolicyBinding` の **責務分離** を理解する
- `replicas` 上限 / image registry 縛りなど **実用ポリシー** を 2 種書く
- Kyverno / OPA Gatekeeper との **立ち位置の違い** を知る (v1.30 GA)

---

## 🤔 なぜ必要？ (ストーリー)

> ある日、上司:「クラスタ全体で `replicas` を 100 以下にしたい。誰かが間違って 10000 を apply した事故が他社で起きた」
>
> あなた:「ValidatingWebhook で書きます」
> → Go で webhook サーバを書く、cert-manager で証明書、Deployment、Service、`ValidatingWebhookConfiguration`、failurePolicy のチューニング…
> → 1 週間後、本番 apiserver が `webhook.example.com` に到達できず **全 apply が固まる**
> → SRE:「自前 webhook が apiserver の手前にいると、こいつが落ちたら全部止まる」
>
> 後日また上司:「`image: ghcr.io/ourcorp/*` 以外を弾きたい」
> → また webhook を立てるの?
>
> 「**ポリシーをコンテナサーバとして外出ししない**」「**apiserver の中で完結する**」、それが KEP-3488 の答え。
> v1.26 alpha → v1.28 beta → **v1.30 GA**。今書くなら **VAP + CEL** が第一選択肢です。

```
ValidatingWebhook        : Pod を 1 つ立てて、cert を回して、apiserver から呼ばせる
  ↓
ValidatingAdmissionPolicy: 「式」を CRD として置くだけ。apiserver 内で評価
```

## ✨ 面白いポイント (設計)

### 1. **ポリシー (定義) と Binding (適用範囲) の分離**

```
ValidatingAdmissionPolicy        : ルール本体。「replicas <= 5」を一度だけ書く
   ↑
ValidatingAdmissionPolicyBinding : どの namespace / どのラベルに当てるか
```

> **痺れ所:** 1 個のポリシーを **dev は warn、prod は deny** のように Binding 側で振り分けられる。
> Gateway API の GatewayClass / Gateway / Route と同じ「**書ける人が違うものはリソースを分ける**」設計。

### 2. **CEL = Common Expression Language**

```cel
object.spec.replicas <= 5
object.spec.template.spec.containers.all(c, c.image.startsWith('registry.k8s.io/'))
```

- **型が決まっている** (object は対象 resource の Schema を持つ): IDE 補完が効く
- **副作用なし**: 評価が予測可能 / キャッシュ可能
- **Go の代わりに 1 行**: コード書かなくていい

> **痺れ所:** CEL は Envoy (RBAC) / Cloud IAM (Condition) / Cloud Armor などでも使われている。**k8s だけのローカル言語ではない**ので、覚える価値が高い。

### 3. **`validations` / `auditAnnotations` / `matchConditions` の三段**

- `matchConditions`: そもそも評価する対象か (= フィルタ。早期 return できる)
- `validations`: 拒否 / 警告 / 監査の 3 モード
- `auditAnnotations`: 通したが audit log に印を残したい時

### 4. **Mutating ではない**

VAP は **書き換えはしない** (Mutating 版は別 KEP で進行中)。 → 「**Kyverno で mutate もしたい**」なら Kyverno を使う、住み分けが明確。

| | ValidatingAdmissionPolicy | Kyverno | OPA Gatekeeper |
|---|---|---|---|
| 設置 | apiserver 標準 | Deployment + webhook | Deployment + webhook |
| 言語 | CEL | YAML DSL + JMESPath/CEL | Rego |
| 失敗時 | apiserver が落ちない | webhook 落ちると詰む | 同左 |
| Mutate | × (将来) | ◯ | △ |
| Generate | × | ◯ | × |
| 学習コスト | 低 (CEL のみ) | 中 | 高 (Rego) |

## 😱 あるある罠

- **`paramKind` を入れずに lat 値をハードコード**: 上限値だけ変えたい時に毎回ポリシーを書き換えることになる → `paramKind` で ConfigMap 参照させると DRY
- **`failurePolicy: Ignore`**: 評価エラーで素通りする。開発時は便利だが本番は `Fail` 推奨
- **CRD 自体を対象にしてしまう**: `matchConstraints` で対象 resource を絞らないと、Lease / Event まで CEL に流れて apiserver が重くなる
- **GVK の version 違い**: `apps/v1` を狙ったつもりが `apps/v1beta1` がそのまま通る → `apiVersions` を明示
- **Binding の `validationActions: [Audit]` のまま運用**: 拒否されると思っていたら audit log にしか出ていなかった
- **CRD バージョン**: `admissionregistration.k8s.io/v1` (GA, v1.30+) を使うこと。`v1beta1` / `v1alpha1` の例が古いブログに残っている

## やること

### 0. 準備

VAP は v1.30 以降の apiserver なら **デフォルトで有効** (`FeatureGate=ValidatingAdmissionPolicy` GA)。Track A の kind v1.33 環境ならそのまま使えます。

```bash
kubectl version --short 2>/dev/null | grep Server
# Server Version: v1.33.x  であることを確認

kubectl create ns ch05-vap
kubectl label ns ch05-vap pod-security.kubernetes.io/enforce=baseline --overwrite
kubectl label ns ch05-vap policy.k8s.io/replicas-cap=enforce --overwrite
```

### 1. ポリシー 1 本目: `replicas <= 5` を強制

```yaml
# vap-replicas-max.yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: replicas-max
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups:   ["apps"]
        apiVersions: ["v1"]
        operations:  ["CREATE", "UPDATE"]
        resources:   ["deployments", "statefulsets", "replicasets"]
  validations:
    - expression: "object.spec.replicas <= 5"
      message: "replicas must be <= 5 (set by ch05 VAP)"
      reason: Invalid
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: replicas-max-binding
spec:
  policyName: replicas-max
  validationActions: [Deny]
  matchResources:
    namespaceSelector:
      matchLabels:
        policy.k8s.io/replicas-cap: enforce
```

```bash
kubectl apply -f vap-replicas-max.yaml
```

**試す:**

```bash
# OK ケース
kubectl -n ch05-vap create deploy ok --image=nginx:1.27 --replicas=3
# 違反ケース
kubectl -n ch05-vap create deploy bad --image=nginx:1.27 --replicas=10
# → Error from server: ... replicas must be <= 5 (set by ch05 VAP)
```

> 別 namespace では当たらないことも確認:
> ```bash
> kubectl create ns ch05-free
> kubectl -n ch05-free create deploy free --image=nginx:1.27 --replicas=20  # ← 通る
> kubectl delete ns ch05-free
> ```

### 2. ポリシー 2 本目: image registry を縛る

```yaml
# vap-image-registry.yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: image-registry-allowlist
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups:   [""]
        apiVersions: ["v1"]
        operations:  ["CREATE", "UPDATE"]
        resources:   ["pods"]
  variables:
    - name: allowedPrefixes
      expression: "['registry.k8s.io/', 'docker.io/library/', 'ghcr.io/']"
  validations:
    - expression: |
        object.spec.containers.all(c,
          variables.allowedPrefixes.exists(p, c.image.startsWith(p)))
      message: "container image must come from an allowed registry (registry.k8s.io / docker.io/library / ghcr.io)"
      reason: Forbidden
    - expression: |
        !has(object.spec.initContainers) ||
        object.spec.initContainers.all(c,
          variables.allowedPrefixes.exists(p, c.image.startsWith(p)))
      message: "initContainer image must come from an allowed registry"
      reason: Forbidden
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: image-registry-allowlist-binding
spec:
  policyName: image-registry-allowlist
  validationActions: [Deny]
  matchResources:
    namespaceSelector:
      matchLabels:
        policy.k8s.io/replicas-cap: enforce  # 同じ ns に当てる
```

```bash
kubectl apply -f vap-image-registry.yaml
```

**試す:**

```bash
# OK (docker.io/library/nginx)
kubectl -n ch05-vap run good --image=docker.io/library/nginx:1.27
# NG (quay.io)
kubectl -n ch05-vap run bad --image=quay.io/prometheus/busybox:latest
# → Error from server: ... container image must come from an allowed registry
```

> **痺れ所:** `variables` で共通リストを定義して、initContainer と container の両方で使い回している。**CEL に変数があるのが嬉しい瞬間**。

### 3. ポリシー 3 本目: `paramKind` でしきい値を ConfigMap から読む

ハードコードを避け、運用で値だけ変えられるようにする。

```yaml
# vap-replicas-param.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: replicas-policy-params
  namespace: ch05-vap
data:
  max: "3"
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: replicas-max-param
spec:
  failurePolicy: Fail
  paramKind:
    apiVersion: v1
    kind: ConfigMap
  matchConstraints:
    resourceRules:
      - apiGroups:   ["apps"]
        apiVersions: ["v1"]
        operations:  ["CREATE", "UPDATE"]
        resources:   ["deployments"]
  validations:
    - expression: "object.spec.replicas <= int(params.data.max)"
      messageExpression: "'replicas must be <= ' + params.data.max"
      reason: Invalid
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: replicas-max-param-binding
spec:
  policyName: replicas-max-param
  validationActions: [Deny]
  paramRef:
    name: replicas-policy-params
    namespace: ch05-vap
    parameterNotFoundAction: Deny
  matchResources:
    namespaceSelector:
      matchLabels:
        policy.k8s.io/replicas-cap: enforce
```

```bash
# 先に 1 本目の strict なポリシーを消して衝突を避ける
kubectl delete validatingadmissionpolicybinding replicas-max-binding
kubectl apply -f vap-replicas-param.yaml

kubectl -n ch05-vap create deploy small --image=nginx:1.27 --replicas=2  # OK
kubectl -n ch05-vap create deploy big   --image=nginx:1.27 --replicas=5  # NG (max=3)

# しきい値だけ書き換え
kubectl -n ch05-vap patch cm replicas-policy-params --type merge -p '{"data":{"max":"10"}}'
kubectl -n ch05-vap create deploy big   --image=nginx:1.27 --replicas=5  # 通るようになる
```

> ポリシー YAML は触らず、ConfigMap だけで挙動が変わる。**運用引き渡しが楽**。

### 4. 監査モード (Audit) と Warn

apply された **既存** リソースを変えずに、まず影響を観測したい時:

```yaml
# vap-binding-audit-warn.yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: replicas-max-soft
spec:
  policyName: replicas-max-param
  validationActions: [Warn, Audit]   # Deny ではない
  paramRef:
    name: replicas-policy-params
    namespace: ch05-vap
    parameterNotFoundAction: Deny
  matchResources:
    namespaceSelector:
      matchLabels: {policy.k8s.io/replicas-cap: enforce}
```

```bash
kubectl delete validatingadmissionpolicybinding replicas-max-param-binding
kubectl apply -f vap-binding-audit-warn.yaml

kubectl -n ch05-vap create deploy big --image=nginx:1.27 --replicas=99
# → kubectl 側に Warning が出る。Pod は作られる。audit log にも記録
```

> **本番投入はこの順序が定石**: `Warn+Audit` → 数日観測 → `Deny`。

### 5. 後片付け

```bash
kubectl delete -f vap-binding-audit-warn.yaml --ignore-not-found
kubectl delete -f vap-replicas-param.yaml --ignore-not-found
kubectl delete -f vap-image-registry.yaml --ignore-not-found
kubectl delete -f vap-replicas-max.yaml --ignore-not-found
kubectl delete ns ch05-vap
```

## やってみて気づくこと

- **Webhook サーバが要らない**: cert-manager も Deployment も Service もない。CRD 2 つだけ
- **`Warn` モードがあるおかげで段階導入できる**: いきなり `Deny` にせず、影響を測ってから移行できる
- **`paramKind` の威力**: ポリシー本体は固定、しきい値だけ運用で変えられる
- **CEL の補完**: `object.spec.replicas` が IDE で型補完される (vscode + cel ext)
- **VAP は "書き換え" は出来ない**: mutating したいなら依然 Kyverno / 自作 webhook が必要 (将来は Mutating Admission Policy KEP-3962 が来る)

## 参考

- ValidatingAdmissionPolicy: https://kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy/
- KEP-3488: https://github.com/kubernetes/enhancements/tree/master/keps/sig-api-machinery/3488-cel-admission-control
- CEL 仕様: https://github.com/google/cel-spec
- CEL Playground: https://playcel.undistro.io/
- Kyverno との比較: https://kyverno.io/blog/2023/05/18/kyverno-vs-kubernetes-admission-policies/
- MutatingAdmissionPolicy (KEP-3962, 進行中): https://github.com/kubernetes/enhancements/tree/master/keps/sig-api-machinery/3962-mutating-admission-policy
