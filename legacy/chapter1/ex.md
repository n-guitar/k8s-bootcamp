# 1 初めてのコンテナ
## stage1: hello nginx docker

### コンテナイメージpull
```bash
# pull image
$ docker pull nginx:1.19

# image確認
$ docker images
$ docker image ls
REPOSITORY                                      TAG          IMAGE ID       CREATED         SIZE
nginx                                           1.19         3169fe28086d   3 days ago      126MB
```


### コンテナ起動
- コンテナの起動
```bash
$ docker run -d -p 80:80 nginx:1.19
```
- ブラウザアクセス<br>
http://localhost:80

- 実行中のコンテナ確認
適当なNAMESがつく。<br>
```bash
$ docker ps
CONTAINER ID   IMAGE                   COMMAND                  CREATED              STATUS          PORTS                    NAMES
77111ed46103   nginx:1.19              "/docker-entrypoint.…"   About a minute ago   Up 59 seconds   0.0.0.0:80->80/tcp       agitated_spence
```
### コンテナ内でコマンド実行
- コマンド実行
```bash
$ docker exec -it {CONTAINER ID} or {NAMES} bash

# container
root@XXXXX:/# cat /etc/os-release
PRETTY_NAME="Debian GNU/Linux 10 (buster)"
NAME="Debian GNU/Linux"
VERSION_ID="10"
VERSION="10 (buster)"
VERSION_CODENAME=buster
ID=debian
root@XXXXX:/# uname -a
Linux 77111ed46103 4.19.104-linuxkit #1 SMP PREEMPT Sat Feb 15 00:49:47 UTC 2020 aarch64 GNU/Linux

root@XXXXX:/# exit

$ docker exec -it {CONTAINER ID} or {NAMES} cat /etc/nginx/nginx.conf
$ docker exec -it {CONTAINER ID} or {NAMES} hoatname
```

### コンテナ停止と起動
- コンテナ停止
```bash
$ docker stop {CONTAINER ID}
```
ブラウザアクセスで接続できないことを確認<br>
http://localhost:80


- コンテナ起動、停止
```bash
$ docker start {CONTAINER ID}
```
ブラウザアクセスで接続でることを確認<br>

```bash
http://localhost:80
$ docker stop {CONTAINER ID}
```

- 停止中のコンテナ確認
```bash
# 実行中のコンテナしか出力されない
$ docker ps

# 停止中のコンテナも出力される
$ docker ps -a
```


### bind port
- 同じportは利用できない。
```bash
$ docker run --rm -p 80:80 nginx:1.18

ocker: Error response from daemon: driver failed programming external connectivity on endpoint funny_tharp (XXXX): Bind for 0.0.0.0:80 failed: port is already allocated.
```

- 別のportは可能。
```bash
$ docker run --rm -p 81:80 nginx:1.18

ocker: Error response from daemon: driver failed programming external connectivity on endpoint funny_tharp (XXXX): Bind for 0.0.0.0:80 failed: port is already allocated.
```
- ブラウザアクセス<br>
http://localhost:80<br>
http://localhost:81<br>

- コンソール出力確認<br>
http://localhost:81にアクセスしながらconsoleを確認<br>
*アクセスログが出力される

- nginx:1.18停止<br>
Ctr + C<br>
`--rm` は停止と同時に削除。


### コンテナの削除
```bash
# 削除
$ doekcr rm {CONTAINER ID}
# 削除されていることを確認
$ doekcr ps -a
```

### containerの揮発性とcopyとvolumeのmount
#### containerの揮発性

- 任意のhtmlページの表示
```bash
# コンテナ起動
$ docker run -d -p 80:80 nginx:1.19
```
- ブラウザアクセス<br>
http://localhost:80/<br>


```bash
# コンテナ内
$ docker exec -it {CONTAINER ID} bash

# container
# nginx.confの内容確認
root@XXXXX:/# cat /etc/nginx/nginx.conf

# onf.d/default.confとlocationの内容確認
root@XXXXX:/# cat /etc/nginx/conf.d/default.conf

# html書き換え・・・したいところですが通常vi等はimageに含めません
root@XXXXX:/# vi /usr/share/nginx/html/index.html
bash: vi: command not found
root@XXXXX:/# echo "<h1>hello nginx</h1>" > /usr/share/nginx/html/index.html
```
- ブラウザアクセス<br>
http://localhost:80/<br>

- コンテナ起動、削除
```bash
# 停止
$ docker start {CONTAINER ID}

# 削除
$ doekcr rm {CONTAINER ID}

# 削除されていることを確認
$ doekcr ps -a
```

- もう一度起動し、先程の編集内容が表示されないことを確認
```bash
# コンテナ起動
$ docker run -d -p 80:80 nginx:1.19
$ docker ps
```
- ブラウザアクセス<br>
http://localhost:80/<br>


#### copy

```bash
# コンテンツ
$ mkdir template
$ echo "<h1>hello nginx copy</h1>" > ./template/index.html

# コンテナ起動
$ docker run -d -p 80:80 nginx:1.19
$ docker ps

# コンテナへホストマシンのファイルをコピー
$ docker cp ./template/index.html {CONTAINER ID}:/usr/share/nginx/html
```
- ブラウザアクセス<br>
http://localhost:80/<br>

- コンテナ起動、削除
```bash
# 停止
$ docker start {CONTAINER ID}

# 削除
$ doekcr rm {CONTAINER ID}

# 削除されていることを確認
$ doekcr ps -a
```

- もう一度起動し、先程の編集内容が表示されないことを確認
```bash
# コンテナ起動
$ docker run -d -p 80:80 nginx:1.19
$ docker ps
```
- ブラウザアクセス<br>
http://localhost:80/<br>

#### volumeのmount


```bash
# コンテンツ
$ echo "<h1>hello nginx volume</h1>" > ./template/index.html

# コンテナの起動
$ docker run -d -p 80:80 -v ${PWD}/template/:/usr/share/nginx/html nginx:1.19
$ docker run -d -p 81:80 -v ${PWD}/template/:/usr/share/nginx/html nginx:1.19
$ docker ps
```
ブラウザアクセス<br>
http://localhost:80/<br>
http://localhost:81/<br>

- コンテナ起動、削除
```bash
# 停止
$ docker start {CONTAINER ID}

# 削除
$ doekcr rm {CONTAINER ID}

# 削除されていることを確認
$ doekcr ps -a
```

- もう一度起動し、先程の編集内容が表示されることを確認
```bash
# コンテナ起動
$ docker run -d -p 80:80 -v ${PWD}/template/:/usr/share/nginx/html nginx:1.19
$ docker ps
```
- ブラウザアクセス<br>
http://localhost:80/<br>

### imageの削除
```bash
# 削除
$ doekcr images

# 削除されていることを確認
$ doekcr rmi  {IMAGE ID}
```

### 練習問題

#### ex1
- `docker ps` で出力されるコンテナ名(NAMES)は任意に設定が可能。任意の名前に変更せよ。
- `docker exec -it {CONTAINER ID} or {NAMES} hoatname` で出力されるhostnameは任意に変更可能。任意の名前に変更せよ。

#### ex2
- `nginx:1.19`と`nginx:1.19-alpine`をimage pullし容量を比較せよ。
- `nginx:1.19-alpine`をdocker runで実行し、ブラウザから接続確認せよ。

#### ex3
- `nginx:1.19-alpine`をdocker runで実行し、コンテナからホストマシンに`docker cp`を使って`/etc/nginx/nginx.conf`をコピーせよ。

#### ex4
- httpd コンテナ`httpd:2.4-alpine`を実行し、ブラウザから接続確認せよ。

#### ex5
- docker hubとは何か調べよ。
- https://hub.docker.com/ で公式イメージを検索せよ。

#### ex6
- `nginx:1.19-alpine`をdocker runで実行し、`docker exec`と`env`コマンドでコンテナ内の環境変数を表示せよ。
- docker run実行時にコンテナ内に任意の環境変数(例 HELLO=hello)を`-e`で引き渡し、`docker exec`と`env`コマンドでコンテナ内の環境変数を表示せよ。
- `複数`の環境変数をコンテナ内に任意の環境変数を`-e`で引き渡せし、`docker exec`と`env`コマンドでコンテナ内の環境変数を表示せよ。

### 練習問題(advanced)
#### ex1
- `Dockerfile`を使い、`docker run -d -p 80:80 {image}`で起動し、`http://localhost:80/`でアクセスした時に、初めから`<h1>hello nginx image</h1>`と表示されるcontainer imageを作成せよ。

#### ex2
- 以下自習問題 002 (docker tutorialとSQL操作)を全て行え。
- https://github.com/n-guitar/go_study#%E8%87%AA%E7%BF%92%E5%95%8F%E9%A1%8C-002-docker-tutorial%E3%81%A8sql%E6%93%8D%E4%BD%9C