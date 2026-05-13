# 10 — Mini App (Web / AP / DB)

## ゴール
これまでの章で学んだオブジェクトを **組み合わせて** 1 つの 3 層アプリを kind 上に公開する。旧 bootcamp のゴール (chapter8) を v1.33 + Gateway API でリブートしたもの。

## 構成イメージ

```
        ┌─────────────────────────────┐
        │ HTTPRoute (host: app.local) │
        └──────────┬──────────────────┘
                   ↓
        ┌───── web (nginx) ──────┐   Deployment + Service (ClusterIP)
        └──────────┬─────────────┘
                   ↓
        ┌────── ap (FastAPI 等) ─┐   Deployment + Service (ClusterIP)
        │  - ConfigMap (config)  │
        │  - Secret (DB pw)      │
        └──────────┬─────────────┘
                   ↓
        ┌────── db (postgres) ───┐   StatefulSet + headless Service + PVC
        └────────────────────────┘
```

## やること (予定)
1. namespace `mini-app` を作り、PSA `baseline` ラベルを付与
2. db: StatefulSet + headless Service + PVC (local-path)
3. ap: Deployment + ConfigMap + Secret + ClusterIP Service
4. web: Deployment + ClusterIP Service
5. Gateway + HTTPRoute で `app.local` を web に向ける
6. host ファイルに `127.0.0.1 app.local` を書いてブラウザで確認
7. ローリング更新と rollback を実演
8. clean up

## TODO
- [ ] `manifests/` の各ファイル
- [ ] ap 用のサンプルアプリ (Dockerfile + ソース) を `app/` 下に
- [ ] アーキ図 `assets/mini-app.png`

## ゴールチェック (= 卒業条件)
- [ ] 全 Pod が `Running`
- [ ] ブラウザ `http://app.local` で AP 経由の DB 値が表示される
- [ ] `kubectl rollout restart deploy/ap` でダウンタイム最小で更新できた
- [ ] PSA `baseline` 配下で全 workload が拒否されずに動いている
