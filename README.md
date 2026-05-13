# k8s bootcamp (v1.33 reboot)

2021/11 (v1.22) 時点から止まっている知識を、2026 年現在の **Kubernetes v1.33** 系に合わせて手を動かしながらキャッチアップするための bootcamp です。

設計の出発点となった調査レポート: [n-guitar/second-brain#143](https://github.com/n-guitar/second-brain/issues/143)

> **最初に読む推奨:** [docs/why-k8s.md](./docs/why-k8s.md) — 「なぜ Kubernetes が要るのか / 設計が痺れる 5 つのポイント」
> 各章 README には 🤔 **なぜ必要？** / ✨ **面白いポイント** / 😱 **あるある罠** のセクションがあります。手を動かす前にぜひ。

## 4 トラック構成

| トラック | 基盤 | ねらい |
|---|---|---|
| [Track 0 — Fundamentals](./track-0-fundamentals/) | kind (Docker) | **k8s 初めての人** 向け。主要オブジェクトを 1 つずつ学んで Web/AP/DB アプリまで |
| [Track A — Local / VM 無し](./track-a-local-kind/) | kind (Docker)| v1.22 → v1.33 の **新機能/破壊的変更** を、ローカルで一通り体験 |
| [Track B — AWS EC2 vanilla](./track-b-ec2-vanilla/) | EC2 + kubeadm + containerd + Cilium | "素の" k8s をクラウド上で組み立てて運用感覚を取り戻す |
| [Track C — EKS](./track-c-eks/) | Terraform + EKS + Karpenter + ALB/Gateway API | マネージドのモダンスタックで実運用に近い形を体験 |

進める順序は **0 → A → B → C** を推奨ですが独立に動くので、興味のあるトラックから着手しても OK です。CKA 等で既に基礎がある人は **Track 0 をスキップして Track A から** で問題ありません。

## 何が学べるか (Issue #143 との対応)

- dockershim 削除後の **containerd / crictl**
- **PodSecurityPolicy 廃止 → Pod Security Admission (PSA)** への移行
- **`registry.k8s.io`** 前提のイメージ運用
- **Sidecar Containers** (KEP-753, v1.33 stable)
- **Gateway API** (v1.0 GA) と Ingress の使い分け
- **ValidatingAdmissionPolicy (CEL)**
- **Cilium / eBPF / kube-proxy replacement / Hubble**
- **DRA / Karpenter / In-place Pod Resize** の現在地
- **GitOps (Argo CD)** と **サプライチェーン (cosign + Kyverno)**

詳細な学習ロードマップは [docs/roadmap.md](./docs/roadmap.md) を参照。

## 対象バージョン

- Kubernetes: **v1.33** (2025/04 リリース系)
- 各トラックの `00-prereqs/` に必要なツールと最低バージョンを記載

## 旧 bootcamp について

VirtualBox / Vagrant / k3s in Docker / chapter1〜9 の旧資材は [`legacy/`](./legacy/) に退避しています。参照は可能ですが、v1.22 以前を前提とした手順なので **そのまま動かない** 箇所が多い点に注意してください (`k8s.gcr.io` → `registry.k8s.io`、dockershim、PSP 等)。

## ライセンス / 注意

- 本リポジトリは学習用。コマンドや YAML をそのまま本番投入しないこと
- AWS を使うトラック (B, C) は **課金が発生** します。各トラックの `99-cleanup/` を必ず実施してください
