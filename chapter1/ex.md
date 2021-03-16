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

### host volumeのmount
- 任意のhtmlページの表示
```bash
# コンテンツ
$ mkdir template
$ echo "<h1>hello nginx</h1>" > ./template/hello.html
$ docker run -d -p 80:80 -v ${PWD}/template/:/usr/share/nginx/html nginx:1.19
```
ブラウザアクセス<br>
http://localhost:80/hello.html<br>


```bash
$ docker stop {CONTAINER ID}
```

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
- httpd コンテナ`httpd:2.4-alpine`を実行し、ブラウザから接続確認せよ。

#### ex4
- docker hubとは何か調べよ。
- https://hub.docker.com/ で公式イメージを検索せよ。
