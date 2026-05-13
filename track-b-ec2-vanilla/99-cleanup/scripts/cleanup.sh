#!/usr/bin/env bash
# Track B 99: cleanup を 1 発で
# 1) k8s 上の Service / PVC / VolumeSnapshot を消す
# 2) AWS 側の取り残し (Volume, Snapshot) を可視化
# 3) terraform destroy
# 4) タグ横断検索で残骸ゼロを確認
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "$SCRIPT_DIR/../../01-terraform-vpc-ec2/terraform" && pwd)"
export KUBECONFIG="${KUBECONFIG:-$SCRIPT_DIR/../../02-kubeadm-bootstrap/kubeconfig}"

echo "==== 1. delete LoadBalancer Services ===="
kubectl get svc -A --no-headers 2>/dev/null | awk '$3=="LoadBalancer" {print $1, $2}' \
  | while read ns name; do
      kubectl -n "$ns" delete svc "$name" --ignore-not-found
    done

echo "==== 2. delete PVCs in all namespaces ===="
for ns in $(kubectl get ns -o name 2>/dev/null | sed 's|namespace/||'); do
  kubectl -n "$ns" delete pvc --all --ignore-not-found 2>/dev/null || true
done

echo "==== 3. delete VolumeSnapshots ===="
for ns in $(kubectl get ns -o name 2>/dev/null | sed 's|namespace/||'); do
  kubectl -n "$ns" delete volumesnapshot --all --ignore-not-found 2>/dev/null || true
done

echo "==== 4. AWS-side leftovers (before destroy) ===="
aws ec2 describe-volumes \
  --filters "Name=tag:Project,Values=k8s-bootcamp" \
  --query 'Volumes[].{Id:VolumeId,State:State}' --output table || true

echo "==== 5. terraform destroy ===="
terraform -chdir="$TF_DIR" destroy -auto-approve

echo "==== 6. cross-region leftover check ===="
for r in us-east-1 us-west-2 ap-northeast-1 eu-west-1; do
  echo "-- $r --"
  aws resourcegroupstaggingapi get-resources --region "$r" \
    --tag-filters Key=Project,Values=k8s-bootcamp \
    --query 'ResourceTagMappingList[].ResourceARN' --output text 2>/dev/null || true
done

echo
echo "DONE. 24h 後に AWS Billing をもう一度確認してください。"
