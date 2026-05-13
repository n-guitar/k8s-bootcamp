# Track 0 — Kubernetes Fundamentals (v1.33)

「Docker は触ったことがあるけど Kubernetes は初めて」の人向けに、**Kubernetes の主要オブジェクトを 1 つずつ手を動かして覚える** 入門トラックです。最後に Web/AP/DB の小さなアプリを組み上げてゴール。

旧 `chapter1〜9` の現代版という位置付けで、`registry.k8s.io` / Pod Security Admission / Gateway API など **2026 年時点の標準** に揃えています。

## 🤔 なぜ Track 0 をやるのか

> **ストーリー:** あなたは `docker run` までは出来る。チームから「次から本番は Kubernetes ね」と言われた。
> ググると `Pod`, `Deployment`, `Service`, `Ingress`, `PVC`, `RBAC` … 名前ばかり出てくる。**それぞれが何の痛みを解消するために生まれたか** を順序立てて知りたい。

Track 0 はその順序で並んでいます。各章は「**この機能が無かったら、あなたはこう困る**」というシーンから始まり、解決として該当オブジェクトを導入します。

## ✨ Track 0 でとくに痺れて欲しい設計

- 全てが **`kind: ...`** のリソースという統一感 (Pod も Service も Role も同じ枠組)
- **ラベルセレクタ** という、ポインタを持たない疎結合 (`app=web` だけで Service と Pod が繋がる)
- 宣言 → Controller の reconcile → 観測の **三角形** が、章を通して何度も登場する
- 最後の `10-mini-app` で、ここまで学んだ部品がパズルのように噛み合う瞬間

## 想定読者

- `docker run` / `docker build` がイメージできる
- YAML を読むのが嫌じゃない
- Kubernetes は触ったことが無いか、ほぼ無い

## 使うクラスタ

Track A と **同じ kind クラスタ** を共有する想定です。まずは [`02-kubectl-and-cluster`](./02-kubectl-and-cluster/) でクラスタを 1 つ立てて、以降の章はその上で続けてください。Track A に進む際もそのまま使えます。

## いきなり試したい人へ

- [QUICKSTART.md](./QUICKSTART.md) — 卒業課題のアプリを 1 コマンドで動かす最短手順 (初回 10〜15 分 / 2 回目 3 分)
- [PREREQUISITES.md](./PREREQUISITES.md) — `docker / kind / kubectl / helm / make` のインストール
- `./scripts/up.sh` — クラスタ起動 (3 ノード + metrics-server)
- `./scripts/install-gateway.sh` — Gateway API CRD + Envoy Gateway を 1 発で
- `./scripts/down.sh` — 破棄
- `./scripts/doctor.sh` — 困った時の健康診断
- `./scripts/warm-cache.sh` — オフライン (飛行機/出張) 前に全 image を pre-pull

## 章一覧

| # | ディレクトリ | 学ぶこと | キーオブジェクト |
|---|---|---|---|
| 01 | [01-docker-basics](./01-docker-basics/) | コンテナの復習、イメージとレジストリ、なぜオーケストレータが要るか | `docker run`, `docker build` |
| 02 | [02-kubectl-and-cluster](./02-kubectl-and-cluster/) | kind でクラスタ起動、`kubectl` の基本、core component の場所 | Node, kubelet, kube-apiserver |
| 03 | [03-pod-replicaset-deployment](./03-pod-replicaset-deployment/) | 最小単位 Pod から Deployment まで | Pod, ReplicaSet, Deployment |
| 04 | [04-service-and-dns](./04-service-and-dns/) | クラスタ内通信と DNS、Service 4 タイプ | Service (ClusterIP/NodePort/LoadBalancer/ExternalName), CoreDNS |
| 05 | [05-config-and-secret](./05-config-and-secret/) | 設定と機密値の注入、環境変数とファイルマウント | ConfigMap, Secret |
| 06 | [06-storage-pv-pvc](./06-storage-pv-pvc/) | 永続ボリュームと StorageClass、CSI とは | PV, PVC, StorageClass |
| 07 | [07-scheduling](./07-scheduling/) | nodeSelector / Taint・Toleration / Affinity / topologySpreadConstraints | Scheduler の動き |
| 08 | [08-gateway-api](./08-gateway-api/) | 外部公開を **Gateway API** で。Ingress は補足程度 | GatewayClass, Gateway, HTTPRoute |
| 09 | [09-rbac-and-psa](./09-rbac-and-psa/) | RBAC と Pod Security Admission の基本 | Role, RoleBinding, SA, PSA labels |
| 10 | [10-mini-app](./10-mini-app/) | Web (nginx) / AP (FastAPI 等) / DB (postgres) を組み合わせて公開 | 復習 |

## 「旧 Ingress じゃないの？」と思った人へ

旧 bootcamp は Ingress 中心でしたが、本トラックは **Gateway API (v1.0 GA, 2023/10)** を入口に教えます。理由:

- これから新規に学ぶ人が、Ingress アノテーション地獄を経験する必要はない
- Gateway API は CRD なので、Service Mesh (Istio Ambient 等) でも同じ知識が使える
- 現場で残っている Ingress は 08 章末で「歴史」として軽く触れる

## このトラックを終えると

- Pod / Deployment / Service / ConfigMap / Secret / PVC / Gateway API / RBAC / PSA がそれぞれ何を解決するか説明できる
- 簡単なアプリを YAML で書いて kind 上に公開できる
- Track A の v1.22 → v1.33 差分章 (Sidecar / VAP / Cilium / Argo CD / 等) にスムーズに進める

## 自己反省レビュー

[docs/reflection-track-0.md](../docs/reflection-track-0.md) に「学習者目線でこの教材は楽しいか / 理解できるか / ハードルは妥当か」のフィードバックを記録しています。気付いた問題点・改善案を PR / Issue 歓迎です。
