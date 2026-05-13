# なぜ Kubernetes は要るのか / 何がそんなに面白いのか

> このドキュメントは bootcamp 全体の **前置き**。各章の「🤔 なぜ必要？」「✨ 面白いポイント」と重複する内容もありますが、まず全体像を 1 枚で掴むためのものです。

---

## 第 1 部 — Why: 痛みの歴史 (ストーリー編)

### Scene 1: 1 台のサーバで動かしていた頃

あなたは 3 人のチームで小さな Web サービスを運用している。サーバは EC2 1 台。

- ある朝、デプロイ用の `git pull && systemctl restart app` を打った
- アプリが SIGKILL で落ちた。ユーザは 5 分間 502 を見た
- Slack に「サイト落ちてる」と通報、土下座

> **学び:** 「リリース = ダウンタイム」というのは、本来そうである必要はない。

### Scene 2: スケールが必要になった

トラフィックが 10x に。LB の裏に EC2 を増やすことにした。

- AMI を焼く、Ansible Playbook を流す、設定が微妙にズレる
- ある日、「アプリの app.conf を変えたい」と言われる
- 5 台 SSH してファイル書き換え、1 台だけ書き忘れて 20% のリクエストがおかしくなる

> **学び:** 「**手動の収束**」は人間がやるべき仕事じゃない。

### Scene 3: 夜中の電話

午前 3 時、PagerDuty。

- worker3 が無応答
- SSH 入って journalctl したらカーネルパニック痕跡
- 再起動、もう一回再起動、ALB から外して別 AMI で立て直し
- 30 分後にようやく復旧

> **学び:** 「死んだら自動で代わりが立つ」が、当たり前であってほしい。

### Scene 4: 環境差異

開発者: 「ローカルだと動くんだけど…」
本番: 「うちは Ubuntu 18.04 で OpenSSL のバージョンが違うので」

> **学び:** OS とアプリは **分離されてほしい**。コンテナがそれをやる。

### Scene 5: 複数アプリの相乗り

1 つの EC2 に nginx と Python アプリと cron と… を詰め込んだら、メモリリーク 1 個でみんな道連れに OOM。

> **学び:** プロセス間の **隔離** と、**そのプロセスを誰が再起動するか** が要る。

---

これらの痛みを「**1 台のサーバ上で頑張る運用**」のままで解決しようとすると、Ansible / Chef / systemd / monit / HAProxy / consul / nomad … が増殖し、コードよりインフラの方が複雑になる。

Kubernetes は、これらに対する **1 つの統一された答え** として登場した:

| 痛み | k8s の答え |
|---|---|
| デプロイで落ちる | **Deployment** がローリング更新で常時 N 個以上を維持 |
| 設定がズレる | **ConfigMap / Secret** とマニフェストで宣言、apply で収束 |
| サーバが死んだ | **ReplicaSet / Node controller** が別 Node で勝手に立て直す |
| 環境差異 | **コンテナイメージ** がアプリと OS を 1 つの artifact に |
| 隔離と再起動 | **kubelet** が Pod を監視、死んだら restartPolicy で復活 |

「**宣言したら、勝手にその状態を維持してくれる**」 — これが Kubernetes の中核です。

---

## 第 2 部 — Wow: 設計が痺れる 5 つのポイント

### Wow 1. **宣言的 API + Reconciliation Loop**

k8s に「Pod を 3 個動かしてくれ」と書くと、Controller は **永遠に**「現在の状態」と「望む状態」を比べ続け、差分があれば埋めようとする。

```
   spec (望む状態)  ←─ ユーザが宣言
        │
        │  controller の reconcile loop
        ↓
   status (今の状態) ←─ kubelet 等が報告
```

このループは **失敗してもリトライし続ける**。一時的にエラーを返してもよい。最終的に収束すればよい。

> **痺れポイント:** これは Google の Borg / Site Reliability Engineering の思想がそのまま API になっている。命令型 (do this then that) でなく、宣言型 (be this) なので、**部分的な失敗にもとても強い**。

### Wow 2. **「全てがリソース」モデル**

Pod も、Service も、Node も、権限 (Role) も、admission policy も、全て **`kind: ...`** で表せる「リソース」。

- API server から見ると、これらは均質な REST オブジェクト
- CRD (Custom Resource Definition) を作れば、自分独自のリソース (`kind: PostgresCluster` 等) を追加できる
- そして既存の RBAC / audit / kubectl がそのまま使える

> **痺れポイント:** "**一級市民にする**" 設計。CRD と Operator の文化はここから来ている。`kubectl get pgcluster` が `kubectl get pod` と同じ感覚で動くのは、API が均質だから。

### Wow 3. **kubelet の "watch + reconcile"**

各 Node の kubelet は API server を **watch** している。`Pod` が「この Node に割り当てられた」と書かれたら、kubelet が引き取って起動する。

逆に Node が落ちたら、Node controller が一定時間後に Pod を「失われた」と判断し、別 Node にスケジュールし直す。

> **痺れポイント:** kubelet と controller は **互いに直接通信していない**。全部 API server (= etcd) を経由する。だからネットワーク分断にも強いし、誰でも介入できる (= operator パターン)。

### Wow 4. **Label Selector ですべてが繋がる**

Pod と Service と NetworkPolicy と HPA は **直接ポインタで繋がっていない**。全て **ラベル** で疎結合している。

```
Service (selector: app=web) ──┐
NetworkPolicy (podSelector: app=web) ──┤── Pod (labels: app=web)
HPA (scaleTargetRef → Deployment) ──┘
```

> **痺れポイント:** 後から HPA を足したい? Pod 側を変える必要は **無い**。NetworkPolicy で絞りたい? ラベル合うものに勝手に効く。「**疎結合 = 後から付け足せる**」という設計の典型例。

### Wow 5. **コンテナだけでなく、ネットワークもストレージも "プラグイン" 化**

- CNI: ネットワーク (Cilium / Calico / Flannel)
- CSI: ストレージ (EBS / EFS / Ceph)
- CRI: コンテナランタイム (containerd / CRI-O)
- DRA (新): デバイス (GPU 等)

すべて **インターフェースだけ k8s が決めて、実装はベンダ/OSS が出す**。だから k8s 本体は「コア」を保ち続けられる。

> **痺れポイント:** これは Unix の "**everything is a file**" や Linux の "**everything is a syscall**" と同じ系譜の **抽象化勝利**。最初に Pod 仕様を抽象化した人は天才。

---

## 第 3 部 — 結局、k8s を学ぶと何が楽しいか

1. **失敗してもクラスタが直してくれる** → 安心して `kubectl delete pod` できる
2. **YAML 1 枚で「望む世界」を書ける** → コードレビューでインフラが議論できる
3. **同じ知識が AWS / GCP / Azure / オンプレで効く** → ベンダ縛りからの解放
4. **Operator パターンで、世界中の人が独自リソースを作っている** → 触り続けるのが楽しい
5. **失敗が「Event」として残る** → デバッグが推理小説みたいになる (`kubectl describe pod` を見て犯人を当てるゲーム)

---

## このリポジトリでの取扱

各章 README には以下のセクションを置いています:

| マーク | 何が書いてあるか |
|---|---|
| 🤔 **なぜ必要？** | この技術が無い世界での痛み (ストーリー調) |
| ✨ **面白いポイント** | 設計の妙、エンジニアリング的に痺れる部分 |
| 😱 **あるある罠** | 現場でハマるポイント、運用の知見 |

これらは "読み物" ですが、各章の **やること (= 手を動かすパート)** の前に置いて、「**なぜ今これをやるのか**」を腑に落としてから始められるようにしています。

楽しんでください。
