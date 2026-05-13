# Learning Roadmap

Issue [n-guitar/second-brain#143](https://github.com/n-guitar/second-brain/issues/143) の章立てを、各トラックのハンズオンにマッピングしたものです。

## 全体像

```
Track A (Local / kind)   : 最短で全主要機能を体験
   ↓
Track B (EC2 vanilla)    : kubeadm でクラスタを"組み立てる"
   ↓
Track C (EKS)            : マネージド + モダン運用スタック
```

## 章 / トピックの対応表

| Issue #143 章 | Track A | Track B | Track C |
|---|---|---|---|
| 2-A dockershim 削除 / containerd / crictl | 01 | 02 | (マネージドなので参照のみ) |
| 2-B PSP 廃止 / PSA | 02 | 02 後段で適用 | 01 |
| 2-C `registry.k8s.io` | 00, 01 | 02 | n/a |
| 3-A Sidecar Containers | 03 | n/a (アプリ側で確認) | n/a |
| 3-B Gateway API | 04 | n/a | 03 |
| 4-A ValidatingAdmissionPolicy (CEL) | 05 | n/a | (option) |
| 6   eBPF / Cilium / Hubble | 06 | 03 | (EKS 上 Cilium は応用) |
| 7   CSI ストレージ | 07 (local-path) | 04 (EBS CSI) | 05 (EBS/EFS CSI) |
| 8-B Karpenter | n/a | n/a | 02 |
| 10  GitOps (Argo CD) | 08 | n/a | 06 |
| 11  サプライチェーン (cosign, Kyverno) | 09 | n/a | 07 |
| 12-A SA Token / Projected Volume | (PSA と併せ) | 02 | 04 (Pod Identity) |
| 15-A cgroup v2 | 前提 (kind base image) | 02 で確認 | 前提 |

## 想定所要時間 (1 セッション = 60〜90 分)

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
