# k8s bootcamp (v1.33 reboot)

2021/11 (v1.22) 時点から止まっている知識を、2026 年現在の **Kubernetes v1.33** 系に合わせて手を動かしながらキャッチアップするための bootcamp です。

設計の出発点となった調査レポート: [n-guitar/second-brain#143](https://github.com/n-guitar/second-brain/issues/143)

## 3 トラック構成

| トラック | 基盤 | ねらい |
|---|---|---|
| [Track A — Local / VM 無し](./track-a-local-kind/) | kind (Docker)| まずローカルで全主要機能を一通り触る。VM や AWS なしで完結 |
| [Track B — AWS EC2 vanilla](./track-b-ec2-vanilla/) | EC2 + kubeadm + containerd + Cilium | "素の" k8s をクラウド上で組み立てて運用感覚を取り戻す |
| [Track C — EKS](./track-c-eks/) | Terraform + EKS + Karpenter + ALB/Gateway API | マネージドのモダンスタックで実運用に近い形を体験 |

進める順序は **A → B → C** を推奨ですが独立に動くので、興味のあるトラックから着手しても OK です。

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
