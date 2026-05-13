# mini-app AP — FastAPI + Postgres

Track 0 卒業課題で使う **本物の小さな AP**。FastAPI で 4 つのエンドポイントを提供。

## エンドポイント

| メソッド | パス | 説明 |
|---|---|---|
| GET | `/` | 起動メッセージ + DB 現在時刻 + 自分の pod 名 |
| GET | `/healthz` | readiness/liveness (DB 接続確認) |
| GET | `/guestbook` | ゲストブック一覧 (最新 50 件) |
| POST | `/guestbook` | `{"name": "...", "msg": "..."}` を追加 |

## 設定 (env)

| 変数 | 既定 | 由来 |
|---|---|---|
| `MESSAGE` | `hello from FastAPI` | ConfigMap |
| `DB_HOST` | `db.mini-app.svc.cluster.local` | (省略可) |
| `DB_PORT` | `5432` | (省略可) |
| `DB_NAME` | `app` | (省略可) |
| `DB_USER` | `app` | (省略可) |
| `DB_PASSWORD` | (必須) | Secret |

## ローカルで build & ロード

kind に直接 image をロード:

```bash
# このディレクトリで
docker build -t mini-ap:0.1 .
kind load docker-image mini-ap:0.1 --name bootcamp
```

→ クラスタの全 Node にイメージがコピーされる。`imagePullPolicy: IfNotPresent` で使える。

## 単体動作確認 (任意)

```bash
docker run --rm -p 8080:8080 \
  -e DB_HOST=host.docker.internal \
  -e DB_PASSWORD=test \
  mini-ap:0.1
# 別ターミナルで
curl http://localhost:8080/
# 注: DB が無いので 500 が返るが、サーバ自体は起動する
```

## 設計メモ

- `lifespan` で asyncpg pool を起動時/終了時に管理 (古い `@app.on_event` は非推奨)
- `CREATE TABLE IF NOT EXISTS` で起動時に自動マイグレーション (= デモなので簡易)
- USER 10001 で動かすので、PSA `restricted` でもそのまま通る
