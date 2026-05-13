# 09 — Supply Chain (cosign + Kyverno verifyImages)

## ゴール
- **cosign** で OCI イメージに **鍵ペア署名** を付ける (ローカル/オフライン環境想定)
- **Kyverno** を入れ、`verifyImages` ポリシーで **未署名イメージを admission で拒否** する
- **SBOM** を `cosign attach sbom` で添付し、`cosign verify-attestation` で検証する
- 「**誰が押し込んだか分からないイメージを信用しない**」というサプライチェーン入口の発想を体感する

---

## 🤔 なぜ必要？ (ストーリー)

> 2021 年、SolarWinds 事件: ビルドパイプライン**そのもの** にマルウェアが混入。「ベンダのコードは信用できる」という前提が破れた。
> 同年、Codecov 事件: bash uploader が乗っ取られ、**何千社の CI 環境変数** が外部送信された。
>
> あなたの会社でも上司:「最近、`ghcr.io/<unknown>/totally-not-malware:latest` を `kubectl apply` で持ち込まれた。誰が、いつ、どこでビルドしたイメージ?」
> → registry のアクセス制御だけでは足りない。**「このイメージは本当に我々がビルドしたか?」** を **クラスタ側で検証** したい。
>
> その答えが **Sigstore (cosign)** + **admission policy (Kyverno verifyImages)** の組み合わせ。
> イメージに **暗号署名** を付け、apiserver の手前で **未署名なら入れない**。

```
昔                : registry 認証 OK = 信用 (= registry が破られたら終わり)
Sigstore 時代     : registry 認証 + 署名検証 + provenance (SLSA) で多層防御
```

## ✨ 面白いポイント (設計)

### 1. **cosign = "OCI registry に署名を保存する"**

イメージのダイジェスト (`sha256:...`) に対する署名を、**同じ registry** に `<digest>.sig` という別 tag で push する。

```
ghcr.io/me/app:v1            → manifest (image)
ghcr.io/me/app:sha256-<...>.sig → manifest (signature)
```

> **痺れ所:** **registry を変えない / DB を増やさない**。OCI registry が "なんでも置ける箱" であることを利用した、後付けの仕組み。

### 2. **keyless 署名 (Sigstore Fulcio + Rekor)**

`cosign sign` を OIDC ログインで実行すると:
1. **Fulcio** が一時 X.509 証明書を発行 (Subject = OIDC identity)
2. その鍵で署名
3. 署名と証明書を **Rekor** (透明性ログ) に追記

「**鍵管理しなくて良い** + **公開ログで監査可能**」。

> 本章はローカル kind で OIDC が無いので **鍵モード** を使うが、設計思想は押さえておく。

### 3. **`verifyImages` = "admission で公開鍵検証"**

```yaml
verifyImages:
  - imageReferences: ["ghcr.io/me/*"]
    attestors:
      - entries:
          - keys: {publicKeys: "-----BEGIN PUBLIC KEY-----..."}
```

CI が署名 → クラスタが検証。**鍵だけが共有される**。

### 4. **SLSA Provenance / SBOM の attestation**

`cosign attest` は、JSON ドキュメント (SBOM / build provenance / vuln scan 結果 etc) に署名して registry に置ける。

```
イメージ ───── 署名 (誰が)
        ╲──── SBOM attestation (何が入っているか)
         ╲─── SLSA provenance (どう作られたか)
```

> **痺れ所:** イメージに **来歴 (provenance)** が紐づく。`cosign verify-attestation` で「**v1.2.0 はうちの GitHub Actions から出たビルドである**」を機械的に確認できる。

## 😱 あるある罠

- **タグで検証する**: タグは可変。`@sha256:<digest>` で検証しないと、ビルド後にすり替えが可能
- **keyless 署名をオフライン環境で**: Fulcio / Rekor へ到達できないと sign / verify が失敗。社内 Fulcio を立てるか、鍵モードへ
- **Kyverno を `restricted` namespace に**: Kyverno 自体に CAP_NET_BIND など要らないが、デフォルトの labelMutating 周りで `baseline` 推奨
- **`verifyImages` に **`imageReferences: ["*"]`** を本番初日から**: `kube-system` の registry.k8s.io イメージまで対象になり、apiserver が起動しない事故。**段階的に**
- **`COSIGN_PASSWORD` を空のまま CI に置く**: 鍵漏洩時に被害甚大。短命鍵 + KMS or keyless が本筋
- **`mutateDigest: true`** にしておかないと、Kyverno は **タグ → digest 置換** をしないので、後で別バイナリがすり替わる余地が残る

## やること

### 0. 準備 — ローカル registry と Kyverno

```bash
# 0-a. ローカル registry を Docker で起動 (kind と同じネットワーク)
docker run -d --restart=always --name local-registry \
  --network kind -p 5001:5000 registry:2 2>/dev/null || true
docker network connect kind local-registry 2>/dev/null || true

# 0-b. kind から push できる宛先名を確認
# kind ネットワーク内なら http://local-registry:5000 として見える
# ホストからは http://localhost:5001

# 0-c. namespace 用意
kubectl create ns ch09-supply
kubectl label ns ch09-supply pod-security.kubernetes.io/enforce=baseline --overwrite
```

**Kyverno install:**

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/ 2>/dev/null || true
helm repo update
helm install kyverno kyverno/kyverno --version 3.3.3 \
  -n kyverno --create-namespace
kubectl -n kyverno wait --for=condition=Available deploy --all --timeout=180s
kubectl get crd | grep kyverno   # ClusterPolicy 等が生えている
```

### 1. cosign 鍵ペアを作る

```bash
# パスフレーズは空でも可 (検証だけが目的)
export COSIGN_PASSWORD=""
cosign generate-key-pair          # cosign.key (秘密鍵), cosign.pub (公開鍵) が出来る
cat cosign.pub
```

### 2. テスト用イメージを push して署名

```bash
# 既存 nginx を local-registry に移し替え
docker pull nginx:1.27
docker tag nginx:1.27 localhost:5001/myorg/web:v1
docker push localhost:5001/myorg/web:v1

# digest を取得
DIGEST=$(docker inspect localhost:5001/myorg/web:v1 --format='{{index .RepoDigests 0}}' | cut -d@ -f2)
echo "digest=$DIGEST"

# 署名 (ローカル registry は HTTP なので --allow-insecure-registry)
cosign sign --key cosign.key --allow-insecure-registry --yes \
  localhost:5001/myorg/web@${DIGEST}

# 署名された .sig tag が registry に出来ている
curl -s http://localhost:5001/v2/myorg/web/tags/list
# → "tags":["v1","sha256-...sig"]
```

検証:

```bash
cosign verify --key cosign.pub --allow-insecure-registry \
  localhost:5001/myorg/web@${DIGEST} | jq '.[0].critical'
# → "type": "cosign container image signature"
```

### 3. Kyverno `verifyImages` ポリシー — 未署名を弾く

```yaml
# kyverno-verify-images.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-myorg-images
spec:
  validationFailureAction: Enforce      # 違反は admission で拒否
  webhookTimeoutSeconds: 30
  failurePolicy: Fail
  rules:
    - name: verify-signature
      match:
        any:
          - resources:
              kinds: [Pod]
              namespaces: [ch09-supply]
      verifyImages:
        - imageReferences:
            - "local-registry:5000/myorg/*"     # kind 内から見たホスト名
            - "localhost:5001/myorg/*"
          mutateDigest: true                    # tag を digest に書き換え
          required: true
          attestors:
            - entries:
                - keys:
                    publicKeys: |-
                      <COSIGN_PUB_HERE>
```

`<COSIGN_PUB_HERE>` を置換:

```bash
PUB=$(cat cosign.pub)
sed -i.bak "s|<COSIGN_PUB_HERE>|$(echo "$PUB" | sed ':a;N;$!ba;s/\n/\\n                      /g')|" kyverno-verify-images.yaml
# macOS で sed -i に苦戦する場合は手で公開鍵を貼り付け
kubectl apply -f kyverno-verify-images.yaml
```

**動作確認 — 署名済イメージ (Pod は通る):**

```bash
kubectl -n ch09-supply run good \
  --image=local-registry:5000/myorg/web:v1
kubectl -n ch09-supply get pod good
# → Running
# digest 置換も走っているか確認
kubectl -n ch09-supply get pod good -o jsonpath='{.spec.containers[0].image}{"\n"}'
# → local-registry:5000/myorg/web:v1@sha256:...  (mutateDigest 動作)
```

**未署名イメージ (拒否される):**

```bash
docker pull busybox:1.36
docker tag busybox:1.36 localhost:5001/myorg/unsigned:v1
docker push localhost:5001/myorg/unsigned:v1

kubectl -n ch09-supply run bad \
  --image=local-registry:5000/myorg/unsigned:v1
# Error from server: admission webhook "mutate.kyverno.svc" denied the request:
#   failed to verify image local-registry:5000/myorg/unsigned:v1: no matching signatures
```

> **痺れ所:** **registry 認証は通っている** のに、**署名がない** という一点だけで弾かれる。「registry が破られても署名がなければ無効」という多層防御。

### 4. SBOM の attach と検証

```bash
# 4-a. SBOM 生成 (syft が無ければ skip 可)
docker pull anchore/syft:latest >/dev/null
docker run --rm --network kind anchore/syft:latest \
  local-registry:5000/myorg/web:v1 -o spdx-json > web-sbom.spdx.json

# 4-b. attestation として署名付きで attach
cosign attest --key cosign.key --allow-insecure-registry --yes \
  --predicate web-sbom.spdx.json --type spdxjson \
  localhost:5001/myorg/web@${DIGEST}

# 4-c. 検証
cosign verify-attestation --key cosign.pub --allow-insecure-registry \
  --type spdxjson \
  localhost:5001/myorg/web@${DIGEST} | jq '.payloadType'
# → "application/vnd.in-toto+json"
```

> 同じ仕組みで **SLSA provenance** (`--type slsaprovenance`) や **vuln scan 結果** も貼れる。`cosign tree` で全体を可視化:
> ```bash
> cosign tree --allow-insecure-registry localhost:5001/myorg/web:v1
> ```

### 5. (発展) Kyverno で attestation の中身も検証

```yaml
# kyverno-verify-attest.yaml (rule 追加例)
- name: require-spdx-sbom
  match: {any: [{resources: {kinds: [Pod], namespaces: [ch09-supply]}}]}
  verifyImages:
    - imageReferences: ["local-registry:5000/myorg/*"]
      attestations:
        - type: spdxjson
          attestors:
            - entries:
                - keys: {publicKeys: |-
                    <COSIGN_PUB_HERE>}
          conditions:
            - all:
                - key: "{{ creationInfo.created }}"
                  operator: NotEquals
                  value: ""
```

「SBOM **の中身** が条件を満たさないと admission で落とす」までいける。たとえば「`vulnerabilities.high == 0` でなければ拒否」という運用が書ける。

### 6. 後片付け

```bash
kubectl delete -f kyverno-verify-images.yaml --ignore-not-found
kubectl delete ns ch09-supply
helm -n kyverno uninstall kyverno
kubectl delete ns kyverno

# ローカル registry とローカル鍵
docker rm -f local-registry
rm -f cosign.key cosign.pub web-sbom.spdx.json kyverno-verify-images.yaml*
unset COSIGN_PASSWORD
```

## やってみて気づくこと

- 「署名 = 別のイメージ tag として **同じ registry に置く**」設計の簡潔さ。新インフラを増やさない
- admission で **未署名が物理的に入らない** 感触: pull は出来るのに schedule されない
- `mutateDigest: true` で **タグが digest に書き換わる** ので、後からのイメージ差し替え攻撃を封じている
- attestation で SBOM や provenance を **イメージに紐づける** という発想 (= 「来歴の DB を別に持たない」)
- keyless 署名 (Fulcio / Rekor) は本格運用で大きな価値があるが、kind ローカルでは鍵モードが手早い (= Track C で keyless を試す伏線)

## 参考

- cosign: https://docs.sigstore.dev/cosign/overview/
- Sigstore 全体像: https://www.sigstore.dev/
- Kyverno verifyImages: https://kyverno.io/docs/writing-policies/verify-images/
- SLSA: https://slsa.dev/
- in-toto attestation: https://github.com/in-toto/attestation
- SBOM (SPDX): https://spdx.dev/
- OCI Distribution Spec: https://github.com/opencontainers/distribution-spec
