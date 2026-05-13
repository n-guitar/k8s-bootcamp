# legacy/

Kubernetes v1.22 以前を前提に書かれた旧 bootcamp 資材です。新トラック (Track A/B/C) への置き換えに伴い、`legacy/` 配下に退避しました。

## そのまま動かない可能性が高いポイント

- **`k8s.gcr.io`** が出てくる箇所 → 2023/04 以降は `registry.k8s.io` に要置換
- **Docker / dockershim** 前提 (v1.24+ で削除済み)
- **PodSecurityPolicy** (v1.25 で削除済み)
- **Ingress NGINX のアノテーション**主体の手順 (Gateway API への置き換えを検討)
- in-tree volume plugin (AWS EBS / GCE PD 等) は CSI driver に置換要

参照する場合は、上記の差分を頭に入れた上で読んでください。新規に学習するなら新トラック側を使うことを推奨します。

## 一覧

| ディレクトリ | 概要 |
|---|---|
| `chapter1`〜`chapter9` | 旧 bootcamp の章別ハンズオン |
| `k3s_in_doccker` | Docker 上に k3s で multi-node を立てる手順 |
| `k8s_on_lima` | macOS の Lima 上で k8s を動かす手順 |
| `k8s_on_virtualbox`, `k8s_on_virtualbox2` | VirtualBox + Vagrant + kubeadm |
| `package_box` | kubeadm 済イメージを Packaging して起動を高速化 |
| `nfs-server_container` | NFS サーバを Docker で建てる例 |
| `nginx_ingress` / `traefik_ingress` | Ingress Controller の例 |
