# 以下のイメージを利用
- https://github.com/sjiveson/nfs-server-alpine


# k3sと利用実行

```sh
$ cd nfs-server_container

# k3sのnetworkに参加
$ docker run -d -p 2049:2049 --name nfs --privileged -v $pwd/nfsshare:/nfsshare -e SHARED_DIRECTORY=/nfsshare --network=k3s_in_doccker_default itsthenetwork/nfs-server-alpine:12

# IPの確認
# docker上からは名前解決できるが、k3s上からはできない(方法はいくつかあるが)
$ docker exec -it nfs hostname -i
```
