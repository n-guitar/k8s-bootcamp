# 以下のイメージを利用
- https://github.com/sjiveson/nfs-server-alpine


# k3sと利用実行

```sh


# k3sのnetworkに参加 パブリッシュ無し
$ docker run -d --name nfs --privileged -v /tmp:/nfsshare -e SHARED_DIRECTORY=/nfsshare --network=k3s_in_doccker_default itsthenetwork/nfs-server-alpine:12

# k3sのnetworkに参加 データ永続化あり  パブリッシュあり
# 必要に応じてDockerの設定が必要
# You can configure shared paths from Docker -> Preferences... -> Resources -> File Sharing.
# $ cd nfs-server_container
# $ docker run -d -p 2049:2049 --name nfs --privileged -v $pwd/nfsshare:/nfsshare -e SHARED_DIRECTORY=/nfsshare --network=k3s_in_doccker_default itsthenetwork/nfs-server-alpine:12

# IPの確認
# docker上からは名前解決できるが、k3s上からはできない(方法はいくつかあるが)
$ docker exec -it nfs hostname -i
```
