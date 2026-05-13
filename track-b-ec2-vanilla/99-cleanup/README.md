# 99 — Cleanup

## ゴール
**課金停止**。EC2 / EBS / NAT GW / EIP 等の取り残しをゼロにする。

## やること
1. PVC を delete (動的 EBS が残るパターンに注意)
2. `kubectl delete svc --all -A` で LoadBalancer / NLB の取り残し回避
3. `terraform destroy`
4. AWS Console の **Billing / Cost Explorer** で残コストが想定内か確認
5. `Resource Groups Tagging API` で tag `Project=k8s-bootcamp` の残骸を全 region で検索

## TODO
- [ ] cleanup スクリプト (`scripts/cleanup.sh`)
- [ ] 取り残しが多い AWS リソース一覧チェックリスト
