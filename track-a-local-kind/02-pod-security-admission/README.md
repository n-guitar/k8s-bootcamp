# 02 — Pod Security Admission (PSA)

## ゴール
- PSP 廃止 (v1.25) 後のデフォルト機構である **Pod Security Admission** を理解
- namespace ラベルで `baseline` / `restricted` を切り替え、違反 Pod の挙動を観察
- **`warn` → `audit` → `enforce`** の **段階移行** を体感する
- **`AdmissionConfiguration`** でクラスタ全体のデフォルトを設定する例 (kind kubeadm patch)

---

## 🤔 なぜ必要？ (ストーリー)

> あなたは v1.21 時代、`PodSecurityPolicy` (PSP) を真面目に書こうとした。
> ```yaml
> apiVersion: policy/v1beta1
> kind: PodSecurityPolicy
> spec:
>   privileged: false
>   allowPrivilegeEscalation: false
>   requiredDropCapabilities: ['ALL']
>   runAsUser: {rule: MustRunAsNonRoot}
>   seLinux:  {rule: RunAsAny}
>   fsGroup:  {rule: RunAsAny}
>   ...
> ```
> 30 行書いた。ところが **どの PSP が誰の Pod に当たるかは ServiceAccount の RBAC で決まる** という、よく考えると意味不明な仕様。
> 「**この Deployment に当たる PSP はどれ?**」を即答できる人を、4 年で 3 人しか見たことがなかった。
>
> SIG-Auth も気づいた:「**PSP は誰も正しく書けなかった**」
> → v1.21 deprecate, v1.25 削除。
> 代わりに来たのが **Pod Security Admission**。仕様を **3 プロファイル × 3 モード = 9 状態** に圧縮し、**namespace ラベル 1 行で適用**。
>
> 4 年で一番「**割り切りが効いた変更**」かもしれません。

## ✨ 面白いポイント (設計)

### 1. **3 プロファイル × 3 モード だけ**

| プロファイル | 中身 |
|---|---|
| `privileged` | 何でも OK (= 制限なし、システム namespace 向け) |
| `baseline` | 既知の特権昇格を防ぐ最低限 (`privileged`, `hostPID`, `hostPath` 等を禁止) |
| `restricted` | 強化、`runAsNonRoot`, `seccompProfile: RuntimeDefault`, capability drop ALL を強制 |

| モード | 違反時の挙動 |
|---|---|
| `enforce` | API server が **拒否** |
| `audit` | audit ログに記録、Pod は通る |
| `warn` | `kubectl apply` 時に **警告メッセージ** だけ表示 |

適用は **namespace ラベル**:

```yaml
labels:
  pod-security.kubernetes.io/enforce: baseline
  pod-security.kubernetes.io/enforce-version: v1.33
  pod-security.kubernetes.io/audit: restricted
  pod-security.kubernetes.io/warn: restricted
```

> **痺れ所:** PSP がやろうとした「**誰の Pod にどのポリシーが当たるか**」問題を、**「Pod は必ずどこかの namespace に居る → namespace に印を付ければ済む」** と気づいたところに痺れる。同じ機能でも適用モデルを変えただけで 10 倍シンプルになる例。

### 2. **段階移行が組み込み**

> "`warn` で炙り出す → `audit` で長期観察 → `enforce` で締める"

```
        warn                   audit                  enforce
       (人間に    →           (ログに    →           (拒否)
        警告だけ)              記録)
```

これは PSP では誰も自力で書けなかった移行手順。**今は label 1 行で切り替わる**。

### 3. **cluster-wide デフォルト (`AdmissionConfiguration`)**

namespace ラベルが付いてない場合のフォールバックを、apiserver の **AdmissionConfiguration** で決められる:

```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
  - name: PodSecurity
    configuration:
      apiVersion: pod-security.admission.config.k8s.io/v1
      kind: PodSecurityConfiguration
      defaults:
        enforce: "baseline"
        enforce-version: "latest"
        audit:   "restricted"
        warn:    "restricted"
      exemptions:
        namespaces: ["kube-system", "envoy-gateway-system"]
```

> **痺れ所:** 「ラベル付け忘れ」を **fail-safe** にできる。「素朴な ns には baseline を強制、特権 ns だけ exempt」というのが現実解。

## 😱 あるある罠

- **`enforce: restricted` をいきなり既存 ns に**: Pod 全滅 → クラスタ半死。**`warn` から**
- **PSA は "**現在動いている Pod**" には作用しない**: ラベル付け替え後の **新規** Pod に当たる。ラベル変更後に rolling update しないと検査されない
- **`kube-system` を restricted に**: CoreDNS / kube-proxy は **privileged が必要**。システム ns は exempt が普通
- **`restricted` で `runAsNonRoot` を Pod 全体に付けず、コンテナ単位だけにする**: Pod / コンテナ securityContext の継承を見落としがち
- **PSA の labels で `enforce-version` を書き忘れる**: 書かないと "latest" 扱い、k8s upgrade で挙動が変わる可能性
- **PSA は Webhook ではなく組み込み Admission**: latency もエラーモードも apiserver と一蓮托生

## やること

### 0. 準備 (01 章のクラスタを使う)

```bash
kubectl get nodes   # 01 章のクラスタが Ready なら OK
kubectl create ns ch02-psa
```

### 1. baseline を貼って "privileged Pod" が拒否される様子

```bash
kubectl label ns ch02-psa \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/enforce-version=v1.33 \
  --overwrite
```

```yaml
# bad-privileged.yaml
apiVersion: v1
kind: Pod
metadata:
  name: bad-priv
  namespace: ch02-psa
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: ["sleep", "3600"]
      securityContext:
        privileged: true
```

```bash
kubectl apply -f bad-privileged.yaml
# Error from server (Forbidden): error when creating "bad-privileged.yaml":
#   pods "bad-priv" is forbidden: violates PodSecurity "baseline:v1.33":
#   privileged (container "c" must not set securityContext.privileged=true)
```

→ **apiserver で拒否される**。Pod は 1 秒も走らない。

`hostPath` も baseline 違反:

```yaml
# bad-hostpath.yaml
apiVersion: v1
kind: Pod
metadata: {name: bad-hp, namespace: ch02-psa}
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: ["sleep","3600"]
      volumeMounts: [{name: host, mountPath: /host}]
  volumes:
    - name: host
      hostPath: {path: /}
```

```bash
kubectl apply -f bad-hostpath.yaml
# violates PodSecurity "baseline:v1.33": hostPath volumes
```

### 2. `restricted` に上げて挙動を比較

```bash
kubectl label ns ch02-psa \
  pod-security.kubernetes.io/enforce=restricted \
  --overwrite
```

普通の "とりあえずな" busybox Pod は **もう通らない**:

```yaml
# plain.yaml
apiVersion: v1
kind: Pod
metadata: {name: plain, namespace: ch02-psa}
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: ["sleep","3600"]
```

```bash
kubectl apply -f plain.yaml
# violates PodSecurity "restricted:v1.33":
#   allowPrivilegeEscalation != false,
#   unrestricted capabilities,
#   runAsNonRoot != true,
#   seccompProfile
```

通す最小構成 (= **これが restricted で動く Pod の "型"**):

```yaml
# good.yaml
apiVersion: v1
kind: Pod
metadata: {name: good, namespace: ch02-psa}
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    seccompProfile: {type: RuntimeDefault}
  containers:
    - name: c
      image: busybox:1.36
      command: ["sleep","3600"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities: {drop: ["ALL"]}
```

```bash
kubectl apply -f good.yaml
kubectl -n ch02-psa get pod good
# Running
```

### 3. `warn` / `audit` で **段階移行リハーサル**

別 ns を作って、**まだ enforce はしないが警告だけ出す** 状態:

```bash
kubectl create ns ch02-psa-staging
kubectl label ns ch02-psa-staging \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/audit=restricted \
  --overwrite
```

```bash
kubectl apply -f plain.yaml -n ch02-psa-staging
# pod/plain created
# Warning: would violate PodSecurity "restricted:latest":
#   allowPrivilegeEscalation != false, ...
```

→ **Pod は作られる** が、**kubectl 出力に黄色い警告** が出る。CI ログから "問題ある Pod を出している namespace / マニフェスト" を炙り出す典型手法。

`audit` 側は API server の audit log に流れます (kind 標準では audit log を有効化していないので確認はスキップ可)。

### 4. クラスタ全体デフォルトを `AdmissionConfiguration` で

実プロダクションでは、**「新しい ns を作った人が PSA ラベルを忘れた」** を fail-safe にしたい。
apiserver の admission config を kubeadm patches で差し込む例:

`admission-config.yaml`:

```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
  - name: PodSecurity
    configuration:
      apiVersion: pod-security.admission.config.k8s.io/v1
      kind: PodSecurityConfiguration
      defaults:
        enforce: "baseline"
        enforce-version: "latest"
        audit: "restricted"
        warn: "restricted"
      exemptions:
        usernames: []
        runtimeClasses: []
        namespaces: ["kube-system", "local-path-storage", "envoy-gateway-system"]
```

`kind-config-with-psa.yaml` (差し替え版、参考):

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: bootcamp
nodes:
  - role: control-plane
    extraPortMappings:
      - {containerPort: 80, hostPort: 80, protocol: TCP}
      - {containerPort: 443, hostPort: 443, protocol: TCP}
    extraMounts:
      - hostPath: ./admission-config.yaml
        containerPath: /etc/kubernetes/admission-config.yaml
        readOnly: true
    kubeadmConfigPatches:
      - |
        kind: ClusterConfiguration
        apiServer:
          extraArgs:
            admission-control-config-file: /etc/kubernetes/admission-config.yaml
  - role: worker
  - role: worker
```

このクラスタを **新しく作り直す** と、**ラベル無しの ns でも `baseline` が enforce される**:

```bash
# (= デモ用に一度クラスタを作り直す手順。普段は不要)
# kind delete cluster --name bootcamp
# kind create cluster --name bootcamp --image kindest/node:v1.33.0 \
#   --config kind-config-with-psa.yaml
# kubectl create ns ch02-default
# kubectl apply -f bad-privileged.yaml -n ch02-default
# → ラベル無しの ns でも baseline で拒否される
```

> **痺れ所:** これで **「ns 作成時のラベル付け忘れ」がそのままセキュリティ事故にならない**。

### 5. 後片付け

```bash
kubectl delete ns ch02-psa ch02-psa-staging
```

(`AdmissionConfiguration` の検証で作り直した場合は、元の `kind-config.yaml` で `./scripts/up.sh` し直してください)

## やってみて気づくこと

- PSP が解けなかった「**誰の Pod にどのポリシーが当たるか**」を、**namespace への印 1 行** で済ませた割り切りの清々しさ
- `warn` で出る黄色いメッセージは、**移行リハーサル** に強力。本番では `audit` 並走で長期観察してから `enforce` に上げるのが王道
- `restricted` Pod の "型" は 1 度書けば使い回せる: **runAsNonRoot / seccompProfile / drop ALL / allowPrivilegeEscalation=false** の 4 点セット
- PSA で足りない要件 (例:「特定 image だけ許す」「replicas は 10 まで」) は **ValidatingAdmissionPolicy / Kyverno** で補う (05 章)

## 参考

- Pod Security Admission: https://kubernetes.io/docs/concepts/security/pod-security-admission/
- Pod Security Standards: https://kubernetes.io/docs/concepts/security/pod-security-standards/
- AdmissionConfiguration: https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-admission-controller/
- PSP → PSS 対応表: https://kubernetes.io/docs/reference/access-authn-authz/psp-to-pod-security-standards/
- 移行ガイド: https://kubernetes.io/docs/tasks/configure-pod-container/migrate-from-psp/
