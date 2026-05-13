# 10 — Mini App: Web / AP / DB を組み合わせる (卒業課題)

## ゴール
これまでの 9 章で学んだオブジェクトを **組み合わせて**、3 層アプリを kind 上に公開する。
本章は **実際に動く Python (FastAPI) のアプリ** を含み、 `make up` で 1 コマンドで起動できます。
**「Kubernetes 使えてる」** と胸を張れる状態になるのがゴール。

---

## まず動かす (3 行)

```bash
cd 10-mini-app
make up        # build + load + apply + wait (初回 2〜5 分)
make smoke     # POST/GET で動作確認
```

→ JSON が返ったら **既に Web/AP/DB が k8s で動いています**。後は楽しい実験へ進みましょう (本章 "5. 楽しい実験" にジャンプ可)。下記の Why / 設計図は読み物として後追いで OK。

---

## 🤔 なぜ必要？ (ストーリー)

> あなたは部品 (Pod, Deployment, Service, ConfigMap, Secret, PVC, HTTPRoute, RBAC, PSA) を順番に学んだ。
> でも実際のアプリは **これらが噛み合って 1 つのサービス** になっている。
>
> ここで部品を組んで、**よくある 3 層 (Web / AP / DB)** を公開します。
> - 部品同士がどう繋がるかを目で見る
> - "コードを書かずに" 設定だけでデプロイ / 更新 / スケール / ロールバックが回ることを体感
> - PSA `baseline` で全 workload が拒否されずに動く (= 本番想定の最低ライン)

## ✨ 面白いポイント

- アプリ本体は **`main.py` 130 行**。それを **YAML 5 個** がインフラ的に支える
- 各層 (Web / AP / DB) は **Service 名** だけで繋がる (IP も Pod 名も知らない)
- 一度組んだら **DB 再起動 / AP rolling update / Web スケール / ConfigMap 書き換え** が全部 1 行

## 構成図

```
   curl http://localhost/        ← host から
        ↓
   ┌──────────────────────────────────────────────┐
   │  Envoy Gateway (Gateway / HTTPRoute)         │
   │  host: app.local → web Service               │
   └──────────────────────────────────────────────┘
        ↓
   ┌──── web (nginx 2 replicas) ─────┐     ConfigMap: web-config (default.conf)
   └──────────────────┬──────────────┘
                      ↓ proxy_pass
   ┌──── ap (FastAPI 2 replicas) ────┐     ConfigMap: ap-config (MESSAGE)
   │   - /                           │     Secret:    db-cred  (DB_PASSWORD)
   │   - /healthz                    │
   │   - /guestbook  GET/POST        │
   └──────────────────┬──────────────┘
                      ↓ asyncpg
   ┌──── db (postgres 1 replica) ────┐     StatefulSet + headless Service
   │   StatefulSet name: db          │     volumeClaimTemplate: 1Gi (local-path)
   └─────────────────────────────────┘
```

## 前提

- `../scripts/up.sh` 済み (= kind クラスタが動いている)
- Envoy Gateway が入っている (08 章で install 済みのはず。未済なら `../scripts/install-gateway.sh`)

## やること

### 1. アプリを build → kind にロード → deploy

ここまで来たら **コマンド 1 つ**:

```bash
cd 10-mini-app
make up
```

中身は以下を順に実行 (Makefile に書いてある):

1. `docker build -t mini-ap:0.1 app/`     ← FastAPI app のイメージ build
2. `kind load docker-image mini-ap:0.1 --name bootcamp`  ← クラスタの Node に push
3. `kubectl apply -f manifests/`           ← Namespace, DB, AP, Web, Gateway を一発投入
4. `kubectl -n mini-app wait --for=condition=Ready pods --all`  ← 全部 Ready 待ち

### 2. 動作確認 (Smoke test)

```bash
make smoke
```

出力 (例):
```json
{
    "message": "hello from FastAPI on Kubernetes",
    "pod": "ap-6d4f7c4b9c-xq2vk",
    "db_now": "2026-05-13T13:42:11.123456+00:00"
}
{
    "id": 1
}
[
    {
        "id": 1,
        "name": "alice",
        "msg": "hello from k8s!",
        "ts": "2026-05-13T13:42:11.234567+00:00"
    }
]
```

→ DB に書き込んで、別 Pod から読み出せている = **3 層全部繋がっている証拠**。

### 3. 楽しい実験

ここからが本番。

| やる事 | コマンド | 観察ポイント |
|---|---|---|
| **AP を 5 台に増やす** | `kubectl -n mini-app scale deploy/ap --replicas=5` | EndpointSlice が即更新、curl を連打すると `"pod"` が 5 種類に分散 |
| **AP のメッセージを変える** | `kubectl -n mini-app edit cm ap-config` (MESSAGE を書換) | env 注入なので Pod 再起動まで反映されない (= ConfigMap 章の知識を再確認) |
| **AP をローリング再起動** | `kubectl -n mini-app rollout restart deploy/ap` | curl ループしながら見るとダウンタイム 0 で MESSAGE が切り替わる |
| **AP を v0.2 にロールアウト** | (image を `mini-ap:0.2` に修正して apply) | `kubectl rollout status` で進捗が見える |
| **ロールバック** | `kubectl -n mini-app rollout undo deploy/ap` | 旧 ReplicaSet が再びスケールアウト |
| **DB Pod を消す** | `kubectl -n mini-app delete pod db-0` | StatefulSet が `db-0` を復元、PVC データは残る |
| **Web を 0 にする** | `kubectl -n mini-app scale deploy/web --replicas=0` | curl が 503 (Gateway 側の backend なし) |
| **PSA 違反 Pod を試す** | `kubectl -n mini-app run bad --image=busybox --privileged -- sleep 9999` | "violates PodSecurity baseline" で拒否 |

### 4. curl ループでローリング更新を眺める

別ターミナルで:
```bash
while true; do
  curl -s -H 'Host: app.local' http://localhost/ | jq -r .pod
  sleep 0.5
done
```

再起動:
```bash
kubectl -n mini-app rollout restart deploy/ap
```

→ Pod 名が **徐々に新しい hash に置き換わる**。ダウンタイムは無い。`maxUnavailable: 0` の意味を体で覚える瞬間。

### 5. ログをまとめて見る

```bash
make logs
```

`stern` を入れている人は:
```bash
stern -n mini-app -l '!service'   # 全 Pod のログを並行 tail
```

### 6. ゴールチェック (= 卒業条件)

- [ ] `make up` がエラー無く通った
- [ ] `make smoke` で 200 OK / JSON が返り、DB に書き込めた
- [ ] AP の Pod 名が curl レスポンスに反映され、scale すると分散される
- [ ] `kubectl rollout restart` でダウンタイム 0 で更新された
- [ ] `kubectl delete pod db-0` してもデータが残る
- [ ] PSA baseline で全 workload が拒否されずに動いている

### 7. 後片付け

```bash
make delete   # namespace mini-app を消す
# クラスタごと消したいなら:
cd .. && ./scripts/down.sh
```

## やってみて気づくこと

- **YAML 5 ファイル + Python 130 行 = 1 つの本格的なアプリ**
- 各層は **Service 名** だけで疎結合 (IP も Pod 名も知らない)
- ConfigMap の env 注入は再起動が要る / volume マウントは自動更新、の違いが現場でそのまま使える
- StatefulSet は Pod 名が固定 (`db-0`) で、消しても PVC とともに復元する
- 「**たった 1 つの YAML 修正 + apply** で本番が変わる」感触が、k8s を使い続けたくなる理由

> **おめでとう! Track 0 卒業です。**
> 次は [Track A](../../track-a-local-kind/) で v1.22 → v1.33 の新機能群へ。

## ファイル一覧

```
10-mini-app/
├── README.md         (このファイル)
├── Makefile          (build / load / deploy / smoke / delete)
├── app/
│   ├── Dockerfile    (multi-stage, non-root, PSA restricted OK)
│   ├── main.py       (FastAPI, asyncpg)
│   ├── requirements.txt
│   └── README.md
└── manifests/
    ├── 00-namespace.yaml   (PSA baseline + warn:restricted)
    ├── 10-db.yaml          (Postgres StatefulSet + headless Svc + Secret)
    ├── 20-ap.yaml          (FastAPI Deployment + ConfigMap + Svc)
    ├── 30-web.yaml         (nginx Deployment + ConfigMap + Svc)
    └── 40-gateway.yaml     (Gateway + HTTPRoute)
```

## 参考

- StatefulSet: https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/
- Pod Security Standards: https://kubernetes.io/docs/concepts/security/pod-security-standards/
- Gateway API: https://gateway-api.sigs.k8s.io/
- FastAPI lifespan: https://fastapi.tiangolo.com/advanced/events/
