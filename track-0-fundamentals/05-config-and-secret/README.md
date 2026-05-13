# 05 — ConfigMap と Secret

## ゴール
- アプリの設定をイメージから分離する基本
- ConfigMap / Secret を **環境変数** / **ファイルマウント** で注入
- Secret の制限 (= base64 でしかない) と、KMS / external secret 等の発展

## やること (予定)
1. ConfigMap で `app.conf` を Pod に `/etc/app/` マウント
2. Secret で DB パスワードを env に注入
3. 変更時の **再読み込み挙動** (volume なら自動更新あり、env は再起動が必要) を観察
4. `immutable: true` ConfigMap の体験
5. (発展) External Secrets Operator / SOPS を名前だけ紹介

## TODO
- [ ] `manifests/configmap.yaml`, `secret.yaml`, `pod-using-config.yaml`
- [ ] `kubectl create secret` の各サブコマンド
- [ ] etcd encryption at rest (KMS v2 GA) は Track B/C で扱う旨明記

## 参考
- ConfigMap: https://kubernetes.io/docs/concepts/configuration/configmap/
- Secret: https://kubernetes.io/docs/concepts/configuration/secret/
