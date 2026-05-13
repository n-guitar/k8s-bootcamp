# 99 — Cleanup: 課金を完全に止める

## ゴール
- k8s リソースを **正しい順序で** 削除して、AWS リソース (EBS / ELB) の取り残しを防ぐ
- `terraform destroy` で VPC / EC2 を全消し
- **タグ横断検索** で `Project=k8s-bootcamp` の残骸ゼロを確認
- Billing コンソールで翌日まで請求が伸びていないことを目視

---

## 🤔 なぜ必要？ (ストーリー)

> 「`terraform destroy` 叩いたから大丈夫」 — その油断が **数百ドルの請求** になります。
>
> Terraform は **自分が作ったもの** しか消せません。
> ところが Track B では、k8s 経由で AWS が **動的に作ったリソース** がたくさん残ります:
> - EBS CSI が作った **PVC 経由の EBS Volume**
> - LoadBalancer Service が作った **NLB / Target Group**
> - VolumeSnapshot が作った **EBS Snapshot** (← `terraform destroy` で消えない!)
> - 04 章で手で作った **IAM Role / Instance Profile**
>
> 順番を間違えると、`terraform destroy` 後に「**ENI が attach されてて削除できない**」と詰みます。
> 削除には **作った順の逆順** という鉄則があります。

## ✨ 面白いポイント (設計)

### 1. **"作った順の逆順" は依存関係の自然な現れ**

```
作る順:                          消す順 (逆):
1. VPC / SG / Subnet              5. VPC / SG / Subnet
2. EC2                            4. EC2
3. k8s cluster                    3. k8s リソース (Service / PVC)
4. CSI driver / 動的 PV           2. PVC delete で EBS を返す
5. Service (LoadBalancer)         1. Service delete で NLB を返す
```

> **痺れ所:** "Terraform 管理外で作ったものを先に消す" がコツ。
> k8s が AWS API で **背後でリソースを作る** という性質を理解していないと、必ず取り残しが出る。

### 2. **タグだけが横断検索の頼り (再掲)**

```bash
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Project,Values=k8s-bootcamp \
  --query 'ResourceTagMappingList[].ResourceARN'
```

これで **何が残っているか** を 1 コマンドで一覧できる。
00 章で `default_tags` を仕込んだ意味がここに帰結する。

## 😱 あるある罠

- **`terraform destroy` 直行**: PVC 経由の EBS が `terraform` の外で生きていて、Volume が `available` で残る
- **LoadBalancer Service を消し忘れ**: NLB と Target Group と EIP が孤児に。**$0.025/h** くらいだが地味に効く
- **`kubectl delete ns` で詰まる**: Finalizer が残って Terminating のまま。CSI / Cilium の Pod が消えると Finalizer 解除されるが、Cilium を先に消すと Pod 削除が走らない → **k8s リソースを先に、CNI を後に**
- **EBS Snapshot を放置**: 0.05 USD/GB-月で安いが **永続課金**
- **us-east-1 以外も見るのを忘れる**: 試しに region を変えて作ったまま忘れる事故

## やること

### 0. 準備

```bash
export KUBECONFIG=$PWD/../02-kubeadm-bootstrap/kubeconfig
```

### 1. k8s 上の "AWS リソースを生やすもの" を先に消す

```bash
# LoadBalancer / NodePort Service 全部
kubectl get svc -A | grep -E 'LoadBalancer|NodePort'
kubectl delete svc -A -l '!kubernetes.io/cluster-service' --field-selector spec.type=LoadBalancer || true

# PVC (= EBS Volume を持つもの) を全 ns で
kubectl get pvc -A
for ns in $(kubectl get ns -o name | sed 's|namespace/||'); do
  kubectl -n $ns delete pvc --all --ignore-not-found
done

# VolumeSnapshot (=EBS Snapshot) も消す
kubectl get volumesnapshot -A 2>/dev/null || true
for ns in $(kubectl get ns -o name | sed 's|namespace/||'); do
  kubectl -n $ns delete volumesnapshot --all --ignore-not-found 2>/dev/null || true
done
```

### 2. AWS 側で残っていないかをまず可視化

```bash
# EBS Volume
aws ec2 describe-volumes \
  --filters "Name=tag:Project,Values=k8s-bootcamp" \
  --query 'Volumes[].{Id:VolumeId,State:State,Size:Size}'

# Snapshot
aws ec2 describe-snapshots --owner-ids self \
  --filters "Name=tag:Project,Values=k8s-bootcamp" \
  --query 'Snapshots[].{Id:SnapshotId,Size:VolumeSize}'

# NLB / ELB
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?Tags[?Key==`elbv2.k8s.aws/cluster`]].LoadBalancerArn' || true

# EIP
aws ec2 describe-addresses \
  --filters "Name=tag:Project,Values=k8s-bootcamp" \
  --query 'Addresses[].{Ip:PublicIp,Assoc:AssociationId}'
```

残っていたら手で消す:

```bash
aws ec2 delete-volume --volume-id vol-xxxx
aws ec2 delete-snapshot --snapshot-id snap-xxxx
```

### 3. 04 章で作った IAM を消す (任意)

```bash
ROLE_NAME=k8s-bootcamp-node
# 各 EC2 から detach (停止中でも実行は可能)
for IID in $(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=k8s-bootcamp" \
  --query 'Reservations[].Instances[].InstanceId' --output text); do
  ASSOC=$(aws ec2 describe-iam-instance-profile-associations \
    --filters Name=instance-id,Values=$IID \
    --query 'IamInstanceProfileAssociations[0].AssociationId' --output text)
  [ "$ASSOC" != "None" ] && aws ec2 disassociate-iam-instance-profile --association-id $ASSOC
done

aws iam remove-role-from-instance-profile --instance-profile-name $ROLE_NAME --role-name $ROLE_NAME || true
aws iam delete-instance-profile --instance-profile-name $ROLE_NAME || true
aws iam detach-role-policy --role-name $ROLE_NAME \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy || true
aws iam delete-role --role-name $ROLE_NAME || true
```

### 4. `terraform destroy`

```bash
cd ../01-terraform-vpc-ec2/terraform
terraform destroy -auto-approve
```

> ENI が detach されない等で詰まる時は、上の k8s リソース掃除が不完全。PVC / LoadBalancer を消し直してリトライ。

### 5. **タグ横断検索** で残骸ゼロを確認

```bash
for r in us-east-1 us-west-2 ap-northeast-1 eu-west-1; do
  echo "==== $r ===="
  aws resourcegroupstaggingapi get-resources --region $r \
    --tag-filters Key=Project,Values=k8s-bootcamp \
    --query 'ResourceTagMappingList[].ResourceARN' --output text
done
```

→ 全 region で空のはず。

### 6. Billing 確認

```bash
# 当月の累計
aws ce get-cost-and-usage \
  --time-period Start=$(date -u +%Y-%m-01),End=$(date -u +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --filter '{"Tags":{"Key":"Project","Values":["k8s-bootcamp"]}}' \
  2>/dev/null || echo "(Cost Explorer は有効化が必要)"
```

24 時間後にもう一度実行し、**請求が止まっている** ことを確認 (Cost Explorer は 24h 遅延)。

### 7. Billing アラートと SNS を消すか? (任意)

00 章で作った Billing アラート + SNS Topic は **次回も使える** ので、Track B を再度やるなら残しておくと便利。
完全に閉じるなら:

```bash
aws cloudwatch delete-alarms --alarm-names k8s-bootcamp-billing-10usd --region us-east-1
aws sns delete-topic --topic-arn arn:aws:sns:us-east-1:<acct>:k8s-bootcamp-billing --region us-east-1
```

### 8. 一括スクリプト

`scripts/cleanup.sh` (本リポジトリ同梱) が 1〜5 までを順に実行します。

```bash
./scripts/cleanup.sh
```

> **AWS 料金注意:** "destroy したつもり" が最大の事故源です。**翌日まで Billing を見届ける** ところまでが cleanup。

## やってみて気づくこと

- "destroy = 終わり" ではなく "**翌日の Billing 確認まで cleanup**"
- k8s が **AWS API を経由して作ったもの** (EBS / ELB) は Terraform の外。**k8s から消すのが先**
- タグ運用さえ徹底していれば、cleanup は **タグ検索 → 残骸個別 delete** の機械作業に落ちる
- "**ResourceGroupsTagging API**" は最強の保険。00 章で `default_tags` を仕込んだ価値が花開く瞬間

## 参考
- Resource Groups Tagging API: https://docs.aws.amazon.com/resourcegroupstagging/latest/APIReference/Welcome.html
- AWS Cost Explorer: https://docs.aws.amazon.com/cost-management/latest/userguide/ce-what-is.html
- Deleting a VPC: https://docs.aws.amazon.com/vpc/latest/userguide/delete-vpc.html
- terraform destroy: https://developer.hashicorp.com/terraform/cli/commands/destroy
