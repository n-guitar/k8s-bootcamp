# Quickstart — 一気に Web/AP/DB を動かす

「**とにかく動くものを見たい**」あなたへ。手順をなぞるだけで Web/AP/DB が `http://localhost` で見える状態まで行きます。

中身の理解は後でゆっくり Track 0 の 01〜10 章でどうぞ。**まず動かす** のが Kubernetes を好きになる近道です。

## 所要時間の目安

- **初回**: 10〜15 分 (kind ノードイメージ ~300MB / Envoy Gateway / Postgres / FastAPI 等の image pull が走る)
- **2 回目以降** (キャッシュ済): 3〜4 分

`scripts/up.sh` 等は進捗を `==>` で出すので、初回の待ち時間中は [docs/why-k8s.md](../docs/why-k8s.md) を読むのがおすすめ。

> オフラインで進めたい (飛行機 / 出張) 場合は **事前に** `./scripts/warm-cache.sh` を実行しておくと、ネット無しで Quickstart が通ります。

---

## 0. 前提

[PREREQUISITES.md](./PREREQUISITES.md) で `docker / kind / kubectl / helm / make / jq (任意)` を入れる。

## 1. クラスタ起動 (初回 2〜4 分)

```bash
cd track-0-fundamentals
./scripts/up.sh
```

→ `Node ... Ready` が 3 行出ればクラスタ起動。

## 2. Gateway API 実装を入れる (初回 1〜2 分)

```bash
./scripts/install-gateway.sh
```

中身は Gateway API CRD と Envoy Gateway の helm install です。

## 3. 卒業課題のアプリを一気に投入 (初回 2〜5 分)

```bash
cd 10-mini-app
make up      # build + load + apply + wait
```

## 4. ブラウザ or curl で確認 (10 秒)

`10-mini-app/` ディレクトリで:
```bash
make smoke
```

または手で:
```bash
curl -s -H 'Host: app.local' http://localhost/
# → {"message":"hello from FastAPI on Kubernetes","pod":"ap-...","db_now":"2026-..."}

curl -s -H 'Host: app.local' -H 'Content-Type: application/json' \
  -d '{"name":"alice","msg":"hello"}' http://localhost/guestbook
# → {"id": 1}

curl -s -H 'Host: app.local' http://localhost/guestbook
# → 投稿一覧 (DB に永続化されている)
```

`/etc/hosts` に `127.0.0.1 app.local` を足せば、ブラウザで `http://app.local` でも見られます。

## 5. 消す (10 秒)

```bash
cd 10-mini-app && make delete   # アプリだけ消す
cd .. && ./scripts/down.sh      # クラスタごと消す
```

---

## ここから何をするか?

| 興味 | 進む先 |
|---|---|
| なぜ k8s が必要? 何が面白い? | [`../docs/why-k8s.md`](../docs/why-k8s.md) |
| Pod / Service / Deployment を 1 つずつ理解したい | [`01-docker-basics/`](./01-docker-basics/) から順に |
| Gateway API でカナリアやってみたい | [`08-gateway-api/`](./08-gateway-api/) |
| 旧 chapter1〜9 がどこに対応? | [`../docs/roadmap.md`](../docs/roadmap.md) |

困ったら `./scripts/doctor.sh` でクラスタの健康診断ができます。
