# Learning Roadmap

Issue [n-guitar/second-brain#143](https://github.com/n-guitar/second-brain/issues/143) の章立てを、各トラックのハンズオンにマッピングしたものです。

## 全体像

```
Track 0 (Fundamentals)   : k8s を 1 から。Pod〜Gateway API〜RBAC/PSA、最後に Web/AP/DB
   ↓
Track A (Local / kind)   : v1.22 → v1.33 の新機能/差分を最短で体験
   ↓
Track B (EC2 vanilla)    : kubeadm でクラスタを"組み立てる"
   ↓
Track C (EKS)            : マネージド + モダン運用スタック
```

> Track 0 と Track A は **同じ kind クラスタ** を使い回せます。
> CKA 等で基礎がある人は Track 0 をスキップして OK。

## 章 / トピックの対応表

| Issue #143 章 | Track 0 | Track A | Track B | Track C |
|---|---|---|---|---|
| (前提) Docker / コンテナ | 01 | - | - | - |
| (前提) kubectl / クラスタ構成 | 02 | - | - | - |
| (前提) Pod / Deployment | 03 | - | - | - |
| (前提) Service / DNS | 04 | - | - | - |
| (前提) ConfigMap / Secret | 05 | - | - | - |
| (前提) PV / PVC / SC | 06 | - | - | - |
| (前提) Scheduling | 07 | - | - | - |
| 2-A dockershim 削除 / containerd / crictl | (触れず) | 01 | 02 | (マネージドなので参照のみ) |
| 2-B PSP 廃止 / PSA | 09 (入口) | 02 (発展) | 02 後段で適用 | 01 |
| 2-C `registry.k8s.io` | 全章前提 | 00, 01 | 02 | n/a |
| 3-A Sidecar Containers | n/a | 03 | n/a (アプリ側で確認) | n/a |
| 3-B Gateway API | 08 (入門) | 04 (発展) | n/a | 03 |
| 4-A ValidatingAdmissionPolicy (CEL) | n/a | 05 | n/a | (option) |
| 6   eBPF / Cilium / Hubble | n/a | 06 | 03 | (EKS 上 Cilium は応用) |
| 7   CSI ストレージ | 06 (local-path) | 07 (snapshot 等) | 04 (EBS CSI) | 05 (EBS/EFS CSI) |
| 8-B Karpenter | n/a | n/a | n/a | 02 |
| 10  GitOps (Argo CD) | n/a | 08 | n/a | 06 |
| 11  サプライチェーン (cosign, Kyverno) | n/a | 09 | n/a | 07 |
| 12-A SA Token / Projected Volume | 09 | (PSA と併せ) | 02 | 04 (Pod Identity) |
| 15-A cgroup v2 | 前提 | 前提 (kind base image) | 02 で確認 | 前提 |
| RBAC (基礎) | 09 | - | - | - |
| 3 層アプリの組み立て | 10 | - | - | - |

## 想定所要時間 (1 セッション = 60〜90 分)

- Track 0: 全 10 セッション (= 約 2 週、初学者なら 1 セッション/日が現実的)
- Track A: 全 10 セッション (= 約 1.5 週)
- Track B: 全 8 セッション (= 約 1 週、AWS 料金注意)
- Track C: 全 9 セッション (= 約 1.5 週、AWS 料金注意)

## ローカルだけで触れない/触りづらいもの

詳細は [`track-a-local-kind/README.md`](../track-a-local-kind/README.md) の "制約" 節参照。

- 本物のノード障害 / kubelet フラグ変更
- LoadBalancer 種別ごとの差異 (NLB/ALB/CLB)
- IRSA / Pod Identity (IAM 連携)
- GPU / DRA の実機検証
- EBS/EFS など外部ストレージの実挙動

→ これらは Track B / C で補完します。
