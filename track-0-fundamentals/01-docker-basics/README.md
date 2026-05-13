# 01 — Docker と「なぜオーケストレータが要るか」

## ゴール
- コンテナとは何か、を 1 行で言えるようになる
- `docker run` / `docker build` / `docker push` を手で動かす
- **1 台の Docker** で運用するときに何が辛いかを **体感** し、k8s に進む動機を腑に落とす

---

## 🤔 なぜ必要？ (ストーリー)

> **2014 年、あなたは "アプリの配布" に苦しんでいた。**
>
> 開発機は macOS、本番は Ubuntu 14.04、ステージングは何故か CentOS。
> Python の `requirements.txt` を `pip install` しても、`libpq` のバージョン違いで本番だけ落ちる。
> Ansible で揃えても、ある日 `apt upgrade` した瞬間に OpenSSL が変わってまた落ちる。
>
> 同僚が言った: 「**アプリと OS を 1 つのファイルにできれば、こんな事は起きないんだけどな**」
>
> その 1 つのファイルが、**コンテナイメージ** です。

コンテナは "**実行可能な状態のスナップショット**":
- アプリのコード
- 依存ライブラリ
- /etc の設定
- ユーザ・パーミッション

を 1 つの **OCI Image** (= レイヤ化された tar) にまとめ、どこでも同じように動かせる。
カーネルだけはホストのものを借りる (= VM より遥かに軽い)。

## ✨ 面白いポイント (設計)

### 1. **コンテナ = プロセス + 名前空間 + cgroup**

VM のように OS を丸ごと立てるのではなく、**Linux カーネルの機能 (namespace, cgroup, capabilities)** だけで「あたかも別マシン」のような隔離を作る。

- `mount namespace`: ファイルシステムを別世界に
- `net namespace`: ネットワークスタックを別世界に
- `pid namespace`: プロセス ID 1 番から始まる別世界に
- `cgroup`: CPU / memory の上限を強制

> **痺れ所:** これらは 2008 年頃から Linux に少しずつ入っていた地味な機能。Docker (2013) はそれらを **`docker run` 1 コマンドで束ねた** ことが偉い。発明ではなく、**統合** が偉かった。

### 2. **イメージレイヤ = COW + 共有**

```
Layer 4: COPY ./app /app           ← あなたのアプリ
Layer 3: pip install -r req.txt    ← 依存
Layer 2: apt-get install python3   ← ランタイム
Layer 1: ubuntu:24.04              ← ベース
```

下のレイヤは **イメージ間で共有** される。だから同じ ubuntu base を使う 100 個のイメージで、ubuntu レイヤは 1 個分しかディスクを食わない。

### 3. **OCI = ベンダ中立の仕様**

Docker, containerd, podman, BuildKit, Kaniko … 全部 OCI Image Spec / OCI Runtime Spec に従う。
だから `docker build` で作ったイメージを **containerd の k8s ノード** でそのまま動かせる。

> **痺れ所:** 仕様を切り出した瞬間に、実装の競争が始まり、結果として全員の利益になった。良いオープン標準の典型例。

## 😱 あるある罠

- **`latest` タグを使い続ける**: ある日 `nginx:latest` が pull で 1.27 → 1.28 になり挙動が変わる。本番では **必ず digest または明示タグ**
- **root でコンテナを動かす**: イメージ作者が指定しないと UID 0。k8s 時代の PSA `restricted` では拒否される
- **巨大イメージ**: `apt-get install` してそのままにすると 1GB 超。**multi-stage build** で build 用と run 用を分ける
- **PID 1 のシグナル**: アプリを `CMD ["python", "app.py"]` で動かすとアプリが PID 1 になる。SIGTERM を受け取らないと **graceful shutdown が出来ない** → `tini` か対応した起動方法を使う

## やること

### 1. nginx を動かす

```bash
docker run --rm -d -p 8080:80 --name web nginx:1.27
curl http://localhost:8080
docker logs web
docker exec web ls /usr/share/nginx/html
docker stop web
```

→ ホストに nginx を **インストールしていない** のに、80 番が叩ける。

### 2. 自分のイメージを作る

```dockerfile
# Dockerfile
FROM python:3.12-slim AS build
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

FROM python:3.12-slim
WORKDIR /app
COPY --from=build /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY app.py .
USER 1000:1000
CMD ["python", "app.py"]
```

```python
# app.py
from http.server import HTTPServer, BaseHTTPRequestHandler

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers()
        self.wfile.write(b"hello from container\n")

HTTPServer(("0.0.0.0", 8080), H).serve_forever()
```

```bash
echo "" > requirements.txt
docker build -t myapp:0.1 .
docker run --rm -p 8080:8080 myapp:0.1
```

ポイント:
- `multi-stage` で build キャッシュとランタイムを分けた
- `USER 1000:1000` で **非 root**。これは後の PSA `restricted` で必須

### 3. レジストリに push (ローカル)

```bash
docker run -d --rm --name reg -p 5000:5000 registry:2
docker tag myapp:0.1 localhost:5000/myapp:0.1
docker push localhost:5000/myapp:0.1
curl http://localhost:5000/v2/myapp/tags/list
```

### 4. 1 台 Docker の限界を、3 つの実験で実感する

| 実験 | コマンド | あなたが見るもの |
|---|---|---|
| (a) 落ちたら？ | `docker kill web` | 復旧しない。誰も再起動してくれない |
| (b) スケールしたい | `docker run --name web2 -p 8081:80 ...` | ポートを別にしないと衝突。LB を別途立てる必要 |
| (c) 設定変えたい | `docker exec web vi /etc/nginx/conf.d/default.conf` | コンテナを消すと変更が消える。イメージに焼き直す or volume が必要 |

> **(a)+(b)+(c) を解決するために、ReplicaSet / Service / ConfigMap が要る。**
>
> Track 0 の各章は、この **3 つの痛みへの "復讐戦"** として配置されています:
> - (a) "落ちたら誰も拾わない" → **03 章 (ReplicaSet / Deployment)** で復讐
> - (b) "スケールが面倒、LB は別途" → **04 章 (Service)** で復讐
> - (c) "設定がイメージに焼き込まれる" → **05 章 (ConfigMap / Secret)** で復讐
>
> 次章 02 では、まず **舞台 (= kubectl とクラスタ)** を整えます。

## やってみて気づくこと

- 「コンテナは軽い VM」と説明されがちだが、実体は **隔離されたプロセス**
- イメージは "**毎回作って捨てる**" のが基本。状態は外 (DB / volume) に置く
- `docker run` は単一マシン用。複数マシンに広げるには **誰かが調整役** をやらないといけない — それが k8s

## 参考

- OCI Image Spec: https://github.com/opencontainers/image-spec
- Docker init / signals: https://docs.docker.com/reference/dockerfile/#stopsignal
- なぜ非 root: https://kubernetes.io/docs/concepts/security/pod-security-standards/
