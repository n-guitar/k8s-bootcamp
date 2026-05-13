# Track 0 自己反省レビュー (2026-05-13)

## エグゼクティブサマリ
「Why → Wow → Trap → 手を動かす」の骨格は通っており、ストーリーと痺れポイントの仕込みは十分に効いている。一方、**章間の前提共有が口約束で済まされている箇所**(02 章での kind 起動が QUICKSTART/scripts と二重提示・kind-config も二重提示、08 章での Envoy Gateway を 10 章が暗黙に要求 など)が学習者を「あれ、もう入れたんだっけ?」で詰まらせるリスクが大きい。さらに **PSA `baseline` を ch03〜07 で当たり前のように貼っているのに、PSA 自体の説明は ch09**という時系列の逆転が、初学者には致命的に分かりにくい。

## 観点 1: 楽しいか

### よかった所
- README.md L7-13 と 14-19 で「ストーリー」と「痺れて欲しい設計」を冒頭に置き、**ラベルセレクタ / 宣言→reconcile→観測 / パズルのように噛み合う 10 章** という 3 本の縦串を最初に宣言できているのは強い。
- 03 章 L66 「シンプルなループの繰り返しが、複雑な運用を消す」、08 章 L31-41 の責任分離 3 階層、09 章 L55 の "時間で必ず切れる" の痺れ所など、**抽象的な美辞ではなく具体的な仕組みに紐づいた "痺れ"** になっている。
- 10 章 README.md L107-121 の "楽しい実験" 表は、**やってみたい誘発が 1 表に 8 個** 詰まっており、ここだけで章末の達成感を倍増させている。
- 02 章 L171-176 の `kubectl --v=8` で生 HTTP を見るくだりは、**初学者が "kubectl = 魔法" 観念を捨てる瞬間** が用意されていて秀逸。

### 改善すべき所 (優先度高/中/低)
- [高] **10-mini-app/README.md L113-121 の "楽しい実験" が後ろに埋まりすぎ**。卒業課題で最も楽しい部分なので、ストーリー直後 (= L17 前後) に「**まずこの 8 つで遊べる**」と置いて、`make up` 後にすぐ実験に飛べる動線にしたい。
- [高] **「やってみたい」と思える瞬間が 01〜02 章で不足**。01 章 L131 の "1 台 Docker の限界 3 実験" は素晴らしいが、`docker kill web` で「復旧しない」を見せた直後に **02 章で同じシナリオを ReplicaSet で 1 行解決** という対比演出が無い。01 章末尾 L142 と 02 章冒頭 L13 で繋ぐ "復讐戦" 構造を入れるべき。
- [中] **04 章のストーリー (L13-23) が秀逸なのに、結末の Wow が ch1 で繋がる Service 体感** だけで終わっている。L135-146 で endpointslice を `-w` 観察するくだりはあるが、**「同じシナリオで LB を手作業で組むと何行 / Service なら何行」の比較**があると痺れ度が跳ね上がる。
- [中] 06 章 L138-146 の「Pod 消してもデータ残る」体感は良いが、**写真映え (= Wow) が弱い**。`hostname >> /data/log` を append しておいて `kubectl exec` で表示するなど、**Pod が変わってもデータが連続して見える** 演出が欲しい。
- [低] 07 章 L256-260 「やってみて気づくこと」が項目箇条書きで終わっており、ストーリー冒頭 (L13-26) の "GPU Node に nginx が乗る大事故" の解決を見届けた感が薄い。クロージングで再度シナリオに戻すと締まる。

## 観点 2: 理解できそうか

### よかった所
- 各章が **ゴール → 🤔 ストーリー → ✨ 設計 → 😱 罠 → やること → 気づき** で完全に揃っており、章を跨いでもリズムが崩れない。
- 03 章 L25-31, 05 章 L31-36, 08 章 L31-37 の **テキストで描かれた階層図** はそれぞれ簡潔で誤解を生みにくい。
- 09 章 L46-53 の "SA token 進化表" のように、**時代変遷を表で見せる** 手法が用語の鮮度ギャップを埋めている。

### 改善すべき所 (優先度高/中/低)
- [高] **README.md L4 / 02 章 L41 / 09 章 L72 で `static Pod` / `Pod Security Admission` / `Gateway API` が説明前に登場**。特に README.md L5 で「PSA / Gateway API / registry.k8s.io」が脚注も無しに並ぶ。冒頭は概念名のみ抑え、具体は章で、というガード文を 1 行入れたい。
- [高] **03〜07 章の "0. 準備" で `pod-security.kubernetes.io/enforce=baseline` を貼っているのに、これが何かは 09 章まで説明なし** (例: 03/L93, 04/L81, 05/L73, 06/L85, 07/L117)。初学者は「なぜこの label を毎回貼るのか?」が分からないまま 7 章進むことになる。各章 L0 にひと言「09 章で詳説。今は "Pod の特権昇格を防ぐ標準的なガード" とだけ知っておけば OK」と注記すべき。
- [高] **QUICKSTART.md L25-32 と 08 章 L89-97 で同じ Envoy Gateway install が二重に書かれている**。さらに 10 章 README.md L53-59 にも同じものが書いてある。Single Source of Truth が無いので「QUICKSTART でやった人 / 08 章だけやった人 / 直接 10 章に来た人」の状態が分岐する。`scripts/up.sh` に `--with-gateway` フラグを生やすか、`scripts/install-gateway.sh` を新設して一本化すべき。
- [高] **02 章 L86-101 で `kind-config.yaml` を再掲しているが、トップの `kind-config.yaml` (L1-39) と内容が違う** (ノード数は同じだが zone label / kubeadmConfigPatches / IPv4 強制が無い)。学習者がこちらをコピーすると 07 章の zone spread で詰まる。「リポジトリの kind-config.yaml をそのまま使う、ここでは要素だけ抜粋」と明示するか、`include` 風に促す。
- [中] **05 章 L165-180 のファイルマウント自動更新デモが `kubectl edit cm` 前提**。L177 だけだと初心者は「どこをどう書き換える?」となる。`kubectl patch cm web-config --type merge -p '{"data":{"app.conf":"..."}}'` の例を **コピペで動く形** で併記すべき。
- [中] **04 章 L127-133 の `kubectl run client -it --rm`** は対話 shell を抜けると Pod が消えるが、`nslookup web` を打つ間に Pod が落ちるトラブルの定番。L127 の `curlimages/curl:8.10.1` には `sh` が入っていない (or busybox とは違う) ので、`-- sh` で落ちる可能性が高い。実際には `-- nslookup web` のように **1 ショット実行** に変えるか、`curl -s http://web` 直接の例にすべき。
- [中] **08 章 L210-216 の `curl -s -H 'Host: app.local' http://localhost/`** は kind の portMapping で 80 を host に抜いている前提だが、**MacOS では `sudo` 無しで 80 番をバインドできない**。「kind の listen は問題ないが、curl 側の話ではなく Docker Desktop が転送する」という前提が伝わっていない学習者は、`Connection refused` で詰まる。注意書きを置きたい。
- [中] **07 章 L122-126 で `kubectl label node bootcamp-worker zone=za` を手で貼っているが、トップの kind-config.yaml L34-39 では既に `topology.kubernetes.io/zone: za/zb` が付いている**。重複かつキーが違う (`zone` vs `topology.kubernetes.io/zone`) ため、L225 の `topologyKey: zone` が `topology.kubernetes.io/zone` でないと標準的に動かない。教育上も後者を使うのが筋。
- [低] 03 章 L83 「サーバサイド apply のフィールドオーナーシップ」は **何も説明せずに用語を出している**。初学者は固まる。括弧書きで「= GitOps と HPA を共存させる仕組み、Track A で詳説」のような橋を架けたい。
- [低] 06 章 L156 の `provisioner: rancher.io/local-path` を CSI 相当と書いているが、L48 で「in-tree は完全削除」と言った直後だと矛盾に見える。"local-path-provisioner は外部 controller で CSI ではないが、同じ動的プロビジョニングの考え方" のように補足したい。

## 観点 3: ハードル

### よかった所
- PREREQUISITES.md は OS 別に整理されていて 5 分で読み切れる。L73 のリソース目安 (CPU 4 / メモリ 6GB) は kind 経験者なら必ず引っかかるポイントなので明記されていて良い。
- `scripts/up.sh` は **`set -euo pipefail` + 既存クラスタ検知 + metrics-server まで一気通貫** で、初学者の "あと一歩で動かない" を潰す設計。
- `scripts/doctor.sh` の段階チェック (前提ツール → docker daemon → kind → kubectl → Node → kube-system Pods) は親切。

### 改善すべき所 (優先度高/中/低)
- [高] **QUICKSTART.md が「5 分で動かす」と言っているのに、実測は確実に 5 分を超える**。helm install の wait 180s (L31), Pod wait 180s (L38), さらに `kind create` の image pull (初回 数百 MB) と Envoy Gateway image pull で 5 分は不可能。「**初回は 10〜15 分**、image cache 後は 3 分」と正直に書く方が信頼を失わない。
- [高] **QUICKSTART.md L37 `kubectl apply -f 10-mini-app/manifests/` だけでは動かない**。`mini-ap:0.1` image が無いと AP Pod は `ErrImagePull` で永遠に Pending。Quickstart で `make up` (build+load+deploy) を使うように変更すべき。今のままだと QUICKSTART を文字通りなぞった人が **必ず詰む**。
- [高] **`scripts/up.sh` は Envoy Gateway を入れない**。一方で QUICKSTART.md は別途 helm install を要求し、10 章 README.md も同様。初心者が `up.sh` → `kubectl apply -f manifests/` の素直なコースを辿ると `gatewayClassName: eg` で詰まる。`scripts/up.sh --with-gateway` か `scripts/install-gateway.sh` を提供し、QUICKSTART/08/10 章でそれを呼ぶ形に統一すべき。
- [高] **飛行機 (オフライン) では即詰む箇所が多すぎる**: scripts/up.sh L58 (metrics-server 取得), QUICKSTART L26 (gateway-api CRD), QUICKSTART L29 (helm OCI pull), 各章の image pull (nginx, busybox, postgres, nginxdemos/hello, hashicorp/http-echo, curlimages/curl)。**オフラインでやる前のキャッシュ手順** (例: `make warm-cache` で全 image を pre-pull) を script 化したい。
- [中] **PREREQUISITES.md L41 `curl -L -s https://dl.k8s.io/release/stable.txt` で取得した version で kubectl を入れる**手順は、上流の `stable.txt` がクラスタの v1.33.0 と乖離した場合 (例: v1.34 が出た時) に、kubectl と server の skew が 2 を超えてエラー。`v1.33.0` 周辺をピン留めする例を併記するのが安全。
- [中] **kind-config.yaml L26-31 の `kubeadmConfigPatches` は control-plane の InitConfiguration をパッチしているが、worker ノードには何も付いていない**にもかかわらず、コメント L25 では「将来 AuditPolicy を仕込めるよう予約」とある。control-plane だけ → 嘘ではないが、ingress-ready=true ラベルが付くのも控え目に説明しておくべき。
- [中] **scripts/up.sh L49 の `--wait 120s`** はメモリの少ない (= 6GB ギリ) 環境で確実にタイムアウトする。Failure 時に「`docker system prune` と Docker Desktop のメモリを増やす」案内を出すと脱出しやすい。
- [中] **各章 0. 準備 (例: 03/L91, 09/L103) の `kubectl create ns chXX` で `--dry-run=client -o yaml | kubectl apply -f -` パターンを使っていない**ため、再実行すると `Error from server (AlreadyExists)` が出て初学者がパニック。`kubectl apply -f -` パターンに統一するか、「2 回目以降のエラーは無視して OK」と明記すべき。
- [低] **PREREQUISITES.md には `make` の存在チェックが無い**。10 章は Makefile が前提だが、Linux 最小構成や Windows の WSL 初期状態で `make` が無いケースが普通にある。`apt install build-essential` を追加するか、Makefile を bash script でも代替可能にしたい。
- [低] **doctor.sh L60 が最後の改行で終わっていない** (Read で確認した末尾)。スクリプト末尾の `kubectl get ns -L pod-security.kubernetes.io/enforce` 行の後に空行 / 出力切れの兆し。実害は小さいが、`shellcheck` をかけると指摘される。

## 致命的に直すべきトップ 5

1. **track-0-fundamentals/QUICKSTART.md L37**: `kubectl apply -f 10-mini-app/manifests/` だけでは `mini-ap:0.1` が無いため AP が起動しない → Quickstart は `cd 10-mini-app && make up` を呼ぶ手順に書き換える。
2. **scripts/up.sh + QUICKSTART/08/10 章**: Envoy Gateway install が 3 箇所に重複し、`up.sh` だけ実行した人は 10 章で詰まる → `scripts/install-gateway.sh` (または `up.sh --with-gateway`) に一本化し、各章はそれを呼ぶだけにする。
3. **03〜07 章の "0. 準備" の `pod-security.kubernetes.io/enforce=baseline`**: 説明は 09 章なのに毎章貼られていて初学者が困惑 → 各章 0. 準備の直前に「09 章で詳説、今は『Pod の特権昇格を防ぐガード』とだけ覚えれば OK」の 1 行注釈を入れる。
4. **02 章 L86-101 の kind-config.yaml 再掲が、リポジトリトップの kind-config.yaml と内容が乖離**: zone ラベル無し、IPv4 強制無し、kubeadm patch 無し → 02 章はインライン再掲を止め「リポジトリ直下の `kind-config.yaml` を使ってください」に統一。乖離があると 07 章 topology spread が動かない。
5. **QUICKSTART.md L1 「5 分で動かす」**: 初回は image pull + helm wait で必ず 5 分を超える → 「初回 10〜15 分 / 2 回目以降 3 分」に正直に書き換え、その代わり進捗ログ (`==> ...` の cyan) を活かして「待ち時間に何を学べばよいか」リンクを置く。

## 「ここを直すとぐっと楽しくなる」提案

- **01 章末 → 02 章頭で "復讐戦" 構造を入れる**: 01 章 L131-141 で見せた 3 つの痛み (落ちる / スケール / 設定) を、Track 0 の章番号と紐付けて「(a) は 03 章で、(b) は 04 章で、(c) は 05 章で復讐」と冒頭に図示。学習者が "なぜ次章をやるか" を毎章自分で答えられる。
- **10 章を「実験ファースト」に並べ替え**: 現在 L62-105 が build/deploy で、楽しい実験は L107 以降。卒業課題なので、`make up && make smoke` の 5 行を最上部に置き、「**動いた? じゃあ次の 8 つの実験で k8s を体に叩き込もう**」とテンポを変える。
- **`scripts/warm-cache.sh` で全 image を pre-pull**: 飛行機/出張前に 1 回叩けば、ネット断でも 01〜10 章が全部動く。具体的には `docker pull` リスト (nginx:1.27 / busybox:1.36 / postgres:16-alpine / hashicorp/http-echo:1.0.0 / nginxdemos/hello:plain-text / nginxinc/nginx-unprivileged:1.27-alpine / curlimages/curl:8.10.1 / kindest/node:v1.33.0 / envoyproxy/gateway-helm OCI) を `kind load` で全 Node に流し込む。
