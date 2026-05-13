# Track A — Local / VM 無し (kind ベース)

Docker さえあれば動く、完全ローカル / 完全無料の bootcamp トラックです。Mac / Linux / Windows (WSL2) いずれでも実施可能。

> **このトラックは「v1.22 から v1.33 で何が変わったか」に集中** しています。
> Pod / Service / Deployment などの **基礎から学びたい人は [Track 0 — Fundamentals](../track-0-fundamentals/) から** どうぞ。

## 🤔 なぜ Track A をやるのか

> **ストーリー:** あなたは過去に CKA を取り、運用もしていた。ところが 4 年離れたら、現場の同僚が `crictl` を叩き、`PodSecurityPolicy` の話が通じず、`Ingress` ではなく `HTTPRoute` を書いていた。
> 何が起きた？ — Track A はその「離れていた間に起きた事件」を **1 日 1 章** で追体験するためのものです。

各章は「旧来こうだった」→「v1.22 以降この KEP が来た」→「今こう書く」という **before/after** 構成。

## ✨ Track A でとくに痺れて欲しい設計

- **dockershim 削除**: kubelet と Docker Engine を切り離した結果、CRI という抽象が真に意味を持った
- **Pod Security Admission**: PSP の "誰の何が当たるか分からない" を、namespace ラベル 1 行に圧縮した割り切り
- **Sidecar Containers (KEP-753)**: `initContainers[].restartPolicy: Always` という、API を増やさずに新パターンを表現したエレガンス
- **Gateway API**: アノテーション地獄を、リソース 3 階層 + ロール分離で解いた
- **Cilium / eBPF**: kube-proxy という "誰もが踏んできた性能ボトルネック" をカーネルレベルで置き換えた

## このトラックで体験すること

- `kind` で **multi-node (control-plane×1, worker×2)** クラスタ
- containerd ランタイムと **`crictl`** の使い方
- **Pod Security Admission (PSA)** baseline / restricted
- **Sidecar Containers** (KEP-753)
- **Gateway API** (Envoy Gateway / Cilium Gateway)
- **ValidatingAdmissionPolicy** (CEL)
- **Cilium** + kube-proxy replacement + Hubble
- **CSI** (local-path-provisioner) と VolumeSnapshot
- **Argo CD** で GitOps
- **cosign + Kyverno verifyImages** でサプライチェーン入口

## 章一覧

| # | ディレクトリ | 内容 |
|---|---|---|
| 00 | [00-prereqs](./00-prereqs/) | 必要ツールのインストール (docker, kind, kubectl, helm, cilium-cli, cosign) |
| 01 | [01-cluster-up](./01-cluster-up/) | kind で multi-node クラスタ起動、`crictl` 体験 |
| 02 | [02-pod-security-admission](./02-pod-security-admission/) | PSA を namespace に適用、違反 Pod を観察 |
| 03 | [03-sidecar-containers](./03-sidecar-containers/) | `initContainers` + `restartPolicy: Always` パターン |
| 04 | [04-gateway-api](./04-gateway-api/) | Envoy Gateway を入れて HTTPRoute |
| 05 | [05-validating-admission-policy](./05-validating-admission-policy/) | CEL で Webhook 不要のポリシー |
| 06 | [06-cilium-ebpf](./06-cilium-ebpf/) | Cilium 導入、kube-proxy 置換、Hubble UI |
| 07 | [07-storage-csi](./07-storage-csi/) | local-path-provisioner + VolumeSnapshot |
| 08 | [08-argo-cd](./08-argo-cd/) | Argo CD を入れて自己管理 (app-of-apps) |
| 09 | [09-supply-chain](./09-supply-chain/) | cosign sign + Kyverno verifyImages |

## 前提バージョン (目安)

| ツール | 推奨 |
|---|---|
| Docker | 24+ |
| kind | v0.23+ (`kindest/node:v1.33.x`) |
| kubectl | v1.33.x |
| helm | v3.14+ |
| cilium-cli | v0.16+ |
| cosign | v2.4+ |

## 制約 (ローカルではここまで出来る)

| やりたいこと | 可否 | 備考 |
|---|---|---|
| multi-node | ◯ | kind で 3 ノード以上可 |
| LoadBalancer 型 Service | △ | MetalLB or cloud-provider-kind が必要 |
| Ingress / Gateway API | ◯ | extraPortMappings で host から到達 |
| 本物の Node 障害テスト | △ | コンテナ kill は出来るが kernel panic は不可 |
| kubelet フラグの変更 | △ | kind の kubeadm patches で限定的に可 |
| cgroup v2 必須化の確認 | ◯ | ホスト OS / Docker desktop に依存 |
| EBS/EFS など外部 CSI | × | Track B/C で扱う |
| GPU / DRA 検証 | × | 実機 GPU が必要、Track 外 |
| IRSA / Pod Identity | × | クラウドが必要 → Track C |

→ ローカルで詰まったら **Track B (EC2)** または **Track C (EKS)** で補完。

## 共通ルール

- すべての例で **`registry.k8s.io`** を前提 (`k8s.gcr.io` は使わない)
- すべての namespace に **PSA baseline 以上** を付ける方針
- マニフェストは `manifests/` 下に分離、各章 README に `kubectl apply -f` で実行できるよう統一
