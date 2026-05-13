# 09 — RBAC と Pod Security Admission

## ゴール
- 「**誰が / 何を / どうできるか**」を表現する **RBAC** モデル
- ServiceAccount の **projected / expiring token** (v1.24 以降のデフォルト)
- **Pod Security Admission (PSA)** で namespace 単位にプロファイル適用
- PSP (v1.25 で削除) との違いを把握

---

## 🤔 なぜ必要？ (ストーリー)

> 入社した新人に kubeconfig を渡したら、ある日 `kubectl delete ns production` をやらかした。
> あなたは目を疑った。**全社が落ちた。**
>
> 同じ頃、別のチームの Pod は `privileged: true` でホストのカーネルに直接アクセスしていた。
> セキュリティ監査で指摘:
> 「**コンテナエスケープしたら hostPath で `/` まで読み書きできますね**」
>
> どちらも「**権限を絞れていなかった**」が原因。
> - 人間 / アプリ → API server に対する権限を絞るのが **RBAC**
> - Pod → ホストに対する権限を絞るのが **Pod Security Admission**
>
> 「**最小権限の原則**」を 2 つの層で実現するのが本章のテーマ。

## ✨ 面白いポイント (設計)

### 1. **RBAC = "**動詞 × リソース**" の積で表す**

```
Subject (User / Group / ServiceAccount)
   │  binds
   ↓
Role / ClusterRole  (verbs × resources)
```

```yaml
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs:     ["get", "list", "watch"]
```

> **痺れ所:** 動詞 (verb) と resource を分離したことで、ポリシーの **語彙が小さい**。
> 結果、`kubectl auth can-i list pods` で **即時にテスト可能**。`if (user.name == "alice" && resource.startsWith("p")) ...` みたいなコードに転落していない。

### 2. **ServiceAccount トークンの進化**

| 時代 | 仕組み | 問題 |
|---|---|---|
| 〜v1.21 | Secret 自動作成、無期限トークン | 漏れると永遠に有効、Pod 内に常時マウント |
| v1.22+ | **projected volume + expiring** がデフォルト | 1 時間で expire、再発行は kubelet が watch |
| v1.24+ | SA 作成時の **Secret 自動作成は廃止** | `kubectl create token <sa>` で明示発行 |

> **痺れ所:** **時間で必ず切れる** という制約を入れただけで、漏洩時の被害が桁違いに小さくなる。これは k8s 自身ではなく Vault などの世界の知見が取り込まれた典型。

### 3. **PSA = "**たった 3 つのプロファイル**" に圧縮**

旧 PSP は細かいフィールド (`runAsUser`, `seLinux`, ...) を全部書けたが、**複雑すぎて誰も正しく設定できなかった**。

PSA は **3 つのプロファイルだけ**:

| プロファイル | 何を許す/禁じる |
|---|---|
| `privileged` | 何でも OK (= 制限なし) |
| `baseline` | 既知の特権昇格を防ぐ最低限 (`privileged`, `hostPID`, `hostPath` 等を禁止) |
| `restricted` | 強化、`runAsNonRoot`, `seccompProfile: RuntimeDefault`, capability drop ALL 等を強制 |

適用は **namespace ラベル 1 行**:

```yaml
labels:
  pod-security.kubernetes.io/enforce: baseline
  pod-security.kubernetes.io/audit:   restricted
  pod-security.kubernetes.io/warn:    restricted
```

3 つのモード:
- `enforce`: 違反 Pod を **拒否**
- `audit`: 違反を **audit ログ** に記録 (Pod は通る)
- `warn`: `kubectl apply` 時に **警告メッセージ** だけ

> **痺れ所:** "**段階的に厳しくする**" 手順が組み込みになっている (`warn` → `audit` → `enforce`)。
> 既存 namespace に一気に `enforce: restricted` を貼ると Pod が全滅 → まず `warn` で炙り出すのが王道。

### 4. **PSA で足りない要件は VAP / Kyverno**

PSA は **画一的** なので、「特定 image だけ許す」「replicas は 10 まで」みたいな業務ルールは書けない。
→ **ValidatingAdmissionPolicy (CEL)** か **Kyverno / OPA Gatekeeper** で補完 (Track A 05)。

## 😱 あるある罠

- **`cluster-admin` を雑に配る**: 学習用は OK だが、本番では **絶対に** やらない
- **Role を作ったが Binding を忘れる**: 何も動かないのに「Role 作ったのに」と詰まる
- **PSA `restricted` をいきなり既存 ns に**: Pod が全部 admission 拒否でクラスタが半死。**`warn` から**
- **`kubectl exec` の RBAC を忘れる**: `pods/exec` という **サブリソース** に別途権限が要る
- **SA トークンを `kubectl get secret` で取る古い手順**: v1.24+ は `kubectl create token <sa>` を使う

## やること

### 0. 準備

```bash
kubectl create ns ch09
kubectl label ns ch09 pod-security.kubernetes.io/enforce=baseline --overwrite
```

### 1. ServiceAccount と Role / RoleBinding

```yaml
# rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata: {name: reader, namespace: ch09}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: {name: pod-reader, namespace: ch09}
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: {name: reader-binding, namespace: ch09}
subjects:
  - kind: ServiceAccount
    name: reader
    namespace: ch09
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

```bash
kubectl apply -f rbac.yaml
```

### 2. `kubectl auth can-i` でテスト

```bash
kubectl -n ch09 auth can-i list pods --as=system:serviceaccount:ch09:reader
# → yes
kubectl -n ch09 auth can-i delete pods --as=system:serviceaccount:ch09:reader
# → no
kubectl -n ch09 auth can-i list deployments --as=system:serviceaccount:ch09:reader
# → no (pod-reader Role には deployments が無い)
```

### 3. SA のトークンで API を叩く (RBAC を curl で味わう)

```bash
TOKEN=$(kubectl -n ch09 create token reader --duration=10m)
APISERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
curl -sk -H "Authorization: Bearer $TOKEN" "$APISERVER/api/v1/namespaces/ch09/pods" | head
curl -sk -H "Authorization: Bearer $TOKEN" "$APISERVER/api/v1/namespaces/ch09/services" | head
# → pods は取れる、services は 403 が返る
```

→ "**kubectl は HTTP クライアント、SA トークンを使えば curl でも代替可能**" を体感。

### 4. PSA: baseline 違反を観察

```yaml
# bad-privileged.yaml
apiVersion: v1
kind: Pod
metadata: {name: bad-priv, namespace: ch09}
spec:
  containers:
    - name: c
      image: busybox:1.36
      securityContext:
        privileged: true
      command: ["sleep", "3600"]
```

```bash
kubectl apply -f bad-privileged.yaml
# → Error: violates PodSecurity "baseline": privileged
```

### 5. PSA: `restricted` に上げる

```bash
kubectl label ns ch09 pod-security.kubernetes.io/enforce=restricted --overwrite
```

```yaml
# bad-root.yaml
apiVersion: v1
kind: Pod
metadata: {name: bad-root, namespace: ch09}
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: ["sleep", "3600"]
```

```bash
kubectl apply -f bad-root.yaml
# → Error: violates PodSecurity "restricted": allowPrivilegeEscalation != false, ...
```

通る Pod の最小構成:
```yaml
# good-pod.yaml
apiVersion: v1
kind: Pod
metadata: {name: good, namespace: ch09}
spec:
  securityContext:
    runAsNonRoot: true
    seccompProfile: {type: RuntimeDefault}
  containers:
    - name: c
      image: busybox:1.36
      command: ["sleep", "3600"]
      securityContext:
        allowPrivilegeEscalation: false
        runAsUser: 1000
        capabilities: {drop: ["ALL"]}
```

```bash
kubectl apply -f good-pod.yaml
kubectl -n ch09 get pod good
```

### 6. `warn` / `audit` の使い分け

既存運用に `enforce` をいきなり貼るのは危険。**まず warn で炙り出す**:

```bash
kubectl create ns ch09-staging
kubectl label ns ch09-staging \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/audit=restricted
kubectl apply -f bad-root.yaml -n ch09-staging
# → Pod は作られるが、kubectl に "Warning: would violate ..." が出る
```

→ 移行戦略のリハーサル。

### 7. 後片付け

```bash
kubectl delete ns ch09 ch09-staging
```

## やってみて気づくこと

- RBAC の表現力は **動詞 × resource** という素朴な掛け算。だから読みやすく、テストしやすい
- `kubectl auth can-i` が "**自分の RBAC が想定通りか**" を即確認できる強力なツール
- PSA は **3 プロファイル × 3 モード = 9 状態** だけ。シンプルゆえに運用が回る
- "**warn → audit → enforce**" の段階移行は、本番にも使える方法

## 参考

- RBAC: https://kubernetes.io/docs/reference/access-authn-authz/rbac/
- Pod Security Admission: https://kubernetes.io/docs/concepts/security/pod-security-admission/
- Pod Security Standards: https://kubernetes.io/docs/concepts/security/pod-security-standards/
- SA Token 変更: https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/
- PSP → PSS 対応表: https://kubernetes.io/docs/reference/access-authn-authz/psp-to-pod-security-standards/
