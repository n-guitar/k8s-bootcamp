# Track B — AWS EC2 で Vanilla Kubernetes (kubeadm)

EC2 上に **kubeadm + containerd + Cilium** で素の Kubernetes クラスタを構築するトラックです。マネージドでは触れない etcd / kube-apiserver / kubelet のレイヤを自分で組み立てて運用感覚を取り戻すのが目的。

## 🤔 なぜ Track B をやるのか

> **ストーリー:** EKS は便利だが、API server のフラグや etcd の場所はあなたから隠れている。
> いざ「謎の挙動」に出会った時、**箱の中** を知らないと推理が出来ない。
> Track B はその「箱の中」を一度自分で組み立てるための場所です。

- kubeadm が裏で何を撒いているか (`/etc/kubernetes/`) を **目で見る**
- etcd / kube-apiserver / scheduler / controller-manager が **static Pod として manifest 1 枚** で動いていることに痺れる
- kubelet を再起動して挙動を試せる (マネージドでは禁断)

## ✨ Track B でとくに痺れて欲しい設計

- **static Pod**: control-plane 自体が「Pod」で動くという、k8s のメタっぷり
- **TLS 一式の自動発行**: kubeadm が CA を作り、kubelet を bootstrap token で参加させる流れ
- **CNI plug-in 化**: kubeadm は CNI を **入れない**。「ネットワークはお前が決めろ」というデザイン

> **注意:** EC2 / VPC / EBS の課金が発生します。各章末の後片付け、最後の [`99-cleanup`](./99-cleanup/) を必ず実行してください。

## 構成イメージ

```
              VPC (10.0.0.0/16)
   ┌──────────────────────────────────────┐
   │  Public Subnet                       │
   │   ├─ control-plane (t3.medium)       │
   │   ├─ worker-1     (t3.medium)        │
   │   └─ worker-2     (t3.medium)        │
   │                                      │
   │  Security Group: 6443, 10250, ...    │
   └──────────────────────────────────────┘
                ↓
        Cilium (kube-proxy なし)
        EBS CSI driver (worker からの動的 PV)
```

## 章一覧

| # | ディレクトリ | 内容 |
|---|---|---|
| 00 | [00-prereqs](./00-prereqs/) | AWS CLI / Terraform / SSH 鍵 |
| 01 | [01-terraform-vpc-ec2](./01-terraform-vpc-ec2/) | VPC + 3 EC2 + SG を Terraform で構築 |
| 02 | [02-kubeadm-bootstrap](./02-kubeadm-bootstrap/) | containerd install → kubeadm init/join、PSA cluster default を設定 |
| 03 | [03-cni-cilium](./03-cni-cilium/) | Cilium で CNI + kube-proxy replacement |
| 04 | [04-storage-ebs-csi](./04-storage-ebs-csi/) | AWS EBS CSI driver、動的プロビジョニング |
| 05 | [05-kubeadm-upgrade](./05-kubeadm-upgrade/) | v1.32 → v1.33 へのローリングアップグレード |
| 06 | [06-node-lifecycle](./06-node-lifecycle/) | drain / cordon / worker 追加 / kubelet flag 変更 |
| 99 | [99-cleanup](./99-cleanup/) | `terraform destroy` と請求アラート確認 |

## 想定コスト (目安)

- t3.medium × 3 (us-east-1, On-Demand): 約 $0.125/h → 3 ノードで **約 $0.13/h** ≒ 24h 連続で約 $3
- EBS gp3 30GB × 3: 約 $0.30/月 × 3 = $0.9 (起動中の按分)
- 学習で停止と再開を繰り返すなら、Spot Instance + 停止運用で半額以下に

## 章をまたぐ前提

- AMI: **Ubuntu 24.04 LTS** (cgroup v2, systemd-resolved 前提)
- Kubernetes: **v1.33.x** (`05-kubeadm-upgrade` 用に開始は **v1.32.x** から)
- ランタイム: **containerd 1.7+**
- CNI: **Cilium (kube-proxy replacement あり)**
- イメージレジストリ: **`registry.k8s.io`** のみ

## TODO
- [ ] Terraform module 共通化 (`modules/vpc`, `modules/k8s-node`)
- [ ] cloud-init で containerd / kubeadm を冪等に
- [ ] SSM Session Manager 利用に切り替え (鍵管理省略)
