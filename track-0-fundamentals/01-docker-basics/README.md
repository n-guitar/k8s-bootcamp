# 01 — Docker と「コンテナオーケストレーション」の前提

## ゴール
- コンテナ (= 隔離されたプロセス) のおさらい
- イメージとレジストリ (Docker Hub / GHCR / ECR / `registry.k8s.io`)
- 1 台の Docker では足りない事 (= なぜ k8s が要るか) を言語化

## やること (予定)
1. `docker run -p 8080:80 nginx` で動かして hostname / `docker logs` を確認
2. `Dockerfile` から `docker build` → 自分のイメージ
3. ローカルレジストリ (`registry:2`) に push → pull
4. 1 台で動かす限界の議論: スケール / 自己修復 / 配信戦略 / 設定管理
5. k8s が何をしてくれるか 1 枚絵で整理

## TODO
- [ ] サンプル `Dockerfile` (Python / Go / Node 何か 1 つ)
- [ ] 「k8s が解決すること」の図 (`assets/why-k8s.png`)
- [ ] 旧 chapter1 との対応メモ

## 参考
- OCI Image Spec: https://github.com/opencontainers/image-spec
- containerd: https://containerd.io/
