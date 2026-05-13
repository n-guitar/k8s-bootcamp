# 99 — Cleanup (Track C)

## ゴール
- **課金されている全リソース** (EKS / ALB / NLB / EBS / EFS / NAT GW / EIP / CW Logs / ECR / Snapshot) を停止
- **tag-based** で全 region を grep して残骸を発見
- 翌朝の Cost Explorer で **$0 / 日に戻っている** ことを確認

---

## 🤔 なぜ必要？ (ストーリー)

> 「`terraform destroy` を打ったから安心」— が一番危ない。
> 課金は **Terraform の管理外で残ったリソース** から発生する:
>
> - `kubectl` で作った `Service type=LoadBalancer` → ALB / NLB が **AWS 側にだけ** 残る
> - PVC を消し忘れた → EBS volume が **gp3 で月 $0.5/10GiB** ずつ
> - VolumeSnapshot を取って消し忘れ → EBS Snapshot が **0.05/GB-月**
> - Karpenter が立てた EC2 が **Spot 中断中** に Terraform を destroy → orphan node
> - EFS の MountTarget だけが消えて、**FileSystem が孤児**
> - CloudWatch Log Group がアプリ削除後も残る (`/aws/eks/...`, `/aws/lambda/...`)
> - ALB の **Idle 中の LCU 課金** (ほぼ 0 だが計上はされる)
>
> 「残った ALB / EBS / NAT GW が見つかるかどうかが運命」。
> 本章は **掃除手順** + **検出手順** + **チェックリスト** です。

## ✨ 面白いポイント (設計)

### 1. **tag-based discovery が最強**
> **痺れ所:** `aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=k8s-bootcamp` を全 region で回せば、**Project tag を付けたリソースが全部見える**。
> 00 章で tag を全部に付けた意味がここで効く。

### 2. **削除順序: Workload → LB → 永続化 → Cluster → Network**
> **痺れ所:** 順番を間違えると `DependencyViolation` で VPC が消せず、destroy が **無限ループ**。
> 正しい順は「**LB → ENI 解放 → Cluster → NAT → VPC**」。

### 3. **Cost Explorer の翌日確認**
> **痺れ所:** AWS の課金は **約 24h 遅延**。今日 destroy しても翌日まで請求はチラつく。
> 検証: 翌朝 09:00 に Cost Explorer で **$0/日 (or budget 以下)** を見て初めて安心。

## 😱 あるある罠

- **`kubectl delete ns` だけして満足**: 中の Service type=LB は finalizer で残骸化することあり
- **Argo CD で管理してた Application を root だけ消す**: 子 Application が `cascade=false` で残り、LB も残る
- **`terraform destroy` を `-target` で部分実行**: 順序を Terraform に任せたほうが安全 (全消し時は target 無し)
- **別 region (us-east-1) に置いた ACM 証明書 / Route53**: 動作確認で別 region に作ったきり忘れる
- **CloudWatch Log Group**: 課金は微々たるが累積すると分かりにくい。**retention=7 日** を設定しておくのが本式

## やること

### 0. 棚卸し (destroy 前に "何が居るか" を確認)

```bash
# Project tag で全 region grep
for r in $(aws ec2 describe-regions --query "Regions[].RegionName" --output text); do
  echo "=== $r ==="
  aws --region "$r" resourcegroupstaggingapi get-resources \
    --tag-filters Key=Project,Values=k8s-bootcamp \
    --query 'ResourceTagMappingList[].ResourceARN' --output text
done
```

ここで挙がった ARN が **削除対象の全リスト**。

### 1. クラスタ内 Workload を先に止める

```bash
# Argo CD で管理しているなら root Application を先に消す (子も連鎖削除)
kubectl -n argocd delete application root --cascade=foreground

# 念のため Service type=LoadBalancer を全消し (ALB / NLB が解放される)
kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' \
  | xargs -r -L1 kubectl delete svc -n

# Gateway も消す (ALB Controller が ALB を delete する)
kubectl get gateway -A --no-headers | awk '{print $1, $2}' | xargs -r -L1 sh -c 'kubectl -n $1 delete gateway $2'

# HTTPRoute / Ingress も
kubectl delete httproute -A --all
kubectl delete ingress  -A --all

# 1〜2 分待って ALB が消えたか確認
aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `k8s-`)].LoadBalancerName' --output text
```

### 2. PVC (EBS / EFS) を消す

```bash
# EBS / EFS の PVC を全削除 (reclaim=Delete のものは物理削除)
kubectl get pvc -A --no-headers | awk '{print $1, $2}' | xargs -r -L1 sh -c 'kubectl -n $1 delete pvc $2'

# VolumeSnapshot (取り残し snapshot 課金防止)
kubectl get volumesnapshot -A --no-headers | awk '{print $1, $2}' | xargs -r -L1 sh -c 'kubectl -n $1 delete volumesnapshot $2'

# AWS 側の取り残し snapshot
aws ec2 describe-snapshots --owner-ids self \
  --filters Name=tag:Project,Values=k8s-bootcamp \
  --query 'Snapshots[].SnapshotId' --output text \
  | xargs -r -n1 aws ec2 delete-snapshot --snapshot-id
```

### 3. Karpenter の Node を先に縮める

```bash
# NodePool を消すと Karpenter が node を退場させる
kubectl delete nodepool --all
kubectl delete ec2nodeclass --all
# 念のため AWS 側に残ったインスタンスがないか
aws ec2 describe-instances \
  --filters "Name=tag:karpenter.sh/discovery,Values=bootcamp" "Name=instance-state-name,Values=running,pending" \
  --query 'Reservations[].Instances[].InstanceId' --output text
```

### 4. Terraform destroy

```bash
cd terraform
terraform destroy -auto-approve
# 10〜15 分。失敗時は "DependencyViolation" を読み、残ってる ENI / LB / Subnet 占有を特定
```

destroy が途中で詰まる代表ケース:

| エラー | 原因 | 対処 |
|---|---|---|
| `DependencyViolation: subnet has dependencies` | ALB / ENI が残ってる | `aws ec2 describe-network-interfaces --filters Name=subnet-id,Values=...` |
| `Cannot delete cluster: nodegroups exist` | MNG が残ってる | `aws eks delete-nodegroup ...` |
| `Cannot delete EFS: mount targets exist` | EFS MountTarget が残ってる | `aws efs delete-mount-target ...` |
| EIP detach 失敗 | NAT GW が消えてない | NAT GW を先に release |

### 5. ECR / S3 / CW Logs

ECR repo (07 章) / Terraform state 用 S3 / CloudWatch Logs は **default では残る**。

```bash
# CloudWatch Logs (/aws/eks/<cluster>)
aws logs describe-log-groups --log-group-name-prefix /aws/eks/bootcamp \
  --query 'logGroups[].logGroupName' --output text \
  | xargs -r -n1 aws logs delete-log-group --log-group-name

# ECR (本気でやり直す時のみ。image を消しても良い場合)
aws ecr delete-repository --repository-name k8s-bootcamp/hello --force
```

### 6. 最終確認 (再度 tag grep)

```bash
for r in $(aws ec2 describe-regions --query "Regions[].RegionName" --output text); do
  out=$(aws --region "$r" resourcegroupstaggingapi get-resources \
    --tag-filters Key=Project,Values=k8s-bootcamp \
    --query 'ResourceTagMappingList[].ResourceARN' --output text)
  [ -n "$out" ] && echo "REGION=$r still has: $out"
done
```

→ 何も出なければ理想的。

### 7. 翌朝の Cost Explorer 確認

```
Console → Billing → Cost Explorer
  - Group by: Service
  - Tag filter: Project=k8s-bootcamp
  - 日次グラフを 24〜48h 観察 → $0/日 に落ちていれば OK
```

### 8. チェックリスト (寝る前の儀式)

- [ ] `kubectl get svc -A | grep LoadBalancer` が空
- [ ] `kubectl get gateway,httproute -A` が空
- [ ] `kubectl get pvc -A` が空 (残すなら reclaim=Retain を確認)
- [ ] `aws elbv2 describe-load-balancers` の戻りが空 or 別 project の物だけ
- [ ] `aws ec2 describe-instances --filters Name=tag:Project,Values=k8s-bootcamp Name=instance-state-name,Values=running` が空
- [ ] `aws ec2 describe-volumes --filters Name=tag:Project,Values=k8s-bootcamp Name=status,Values=available,in-use` が空
- [ ] `aws ec2 describe-snapshots --owner-ids self --filters Name=tag:Project,Values=k8s-bootcamp` が空
- [ ] `aws efs describe-file-systems` で bootcamp が無い
- [ ] `aws eks list-clusters` で bootcamp が無い
- [ ] `aws ec2 describe-nat-gateways --filter Name=state,Values=available` で bootcamp が無い
- [ ] CW Log Group `/aws/eks/bootcamp/*` が無い
- [ ] **翌朝の Cost Explorer が $0/日**

## やってみて気づくこと

- 「destroy が綺麗に終わる」状態を作るには **削除順序の知識** が要る
- tag を最初に決めておくと、cleanup が **数行のスクリプト** になる
- Spot 中断中の Node が orphan として残る稀ケースを見つけるのは tag が無いと無理
- 翌朝の Cost Explorer **$0/日** を見たときの安心感は格別

## 参考

- AWS Resource Groups Tagging API: https://docs.aws.amazon.com/resourcegroupstagging/latest/APIReference/Welcome.html
- VPC Dependency 解決: https://docs.aws.amazon.com/vpc/latest/userguide/working-with-vpcs.html#VPC_Deleting
- Cost Explorer: https://docs.aws.amazon.com/cost-management/latest/userguide/ce-what-is.html
- EKS Cluster 削除: https://docs.aws.amazon.com/eks/latest/userguide/delete-cluster.html
