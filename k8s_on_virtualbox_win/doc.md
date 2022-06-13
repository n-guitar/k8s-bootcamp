# 環境構築Windows

## 動作確認済環境
```sh
# win sw_var
> powershell Get-WmiObject Win32_OperatingSystem

SystemDirectory : C:\WINDOWS\system32
Organization    :
BuildNumber     : 19042
RegisteredUser  : user
SerialNumber    : 00329-00000-00003-AA987
Version         : 10.0.19042

# git bash
$ git --version
git version 2.36.1.windows.1
```

## ツール

### WSL
- 公式サイト
    - https://www.microsoft.com/store/productId/9PN20MSR04DW

### oracle vm (virtual box)
- 公式サイト
    - https://www.oracle.com/jp/virtualization/technologies/vm/downloads/virtualbox-downloads.html
    - バージョン 6.1.14 r140239 (Qt5.6.2)

### Vagrant
- 公式サイト
    - https://www.vagrantup.com/downloads
    - 

```sh
$ vagrant -v
Vagrant 2.2.6
```