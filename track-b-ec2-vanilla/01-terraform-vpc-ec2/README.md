# 01 — Terraform で VPC + EC2 を構築

## ゴール
- VPC / Public Subnet / IGW / Route Table / SG を Terraform で 1 発で作る
- Ubuntu 24.04 LTS の EC2 を **control-plane × 1 + worker × 2** で起動
- cloud-init で **containerd v2 / kubeadm / kubelet / kubectl v1.32** を冪等にインストール
- `cgroup v2` / `swap off` / kernel module (`overlay`, `br_netfilter`) を全 Node で確認できる状態にする
- 全リソースに `Project=k8s-bootcamp` / `Track=B` のタグが乗ること

---

## 🤔 なぜ必要？ (ストーリー)

> Kubernetes は「Linux + 適切なネットワーク + 適切なカーネル設定 + コンテナランタイム」が揃って初めて動く。
> EKS や GKE はそこを **全部マネージドが肩代わり** している。だから "簡単" に見える。
>
> ところが現場のトラブルの 7 割は、その **肩代わりされていた層** で起きる:
> - kubelet が Pod を作れない → 実は cgroup driver の不一致
> - Pod 間通信が落ちる → SG で BGP/179 が開いていない
> - Node が NotReady になる → swap が有効のままだった
>
> 一度 **手で組み立てる** と、これらの「k8s より下の層」のチェックリストが体に入る。
> Terraform を使うのは、それを **何度でも壊して作り直せる** ようにするため。

## ✨ 面白いポイント (設計)

### 1. **VPC + SG が k8s の "ネットワーク前提条件" を語っている**

kubeadm のドキュメントには「これらのポートを開けろ」と表が載っているだけだが、実際に SG として書き起こすと **k8s のアーキテクチャが透ける**:

| ポート | 誰 → 誰 | 何 |
|---|---|---|
| 6443/tcp | kubectl / worker → control-plane | kube-apiserver |
| 10250/tcp | control-plane → kubelet (双方向) | `kubectl logs/exec` の実体 |
| 2379-2380/tcp | control-plane 内 | etcd peer / client |
| 8472/udp | Node ↔ Node | Cilium VXLAN (or geneve) |
| 4240/tcp | Node ↔ Node | Cilium health check |
| 30000-32767/tcp | external → Node | NodePort |

> **痺れ所:** "k8s の通信ポリシー" は **SG (L3/L4 ACL) と NetworkPolicy (L3/L4) と CiliumNetworkPolicy (L7) の三層** で表現される。本章ではまず一番下の SG を組む。

### 2. **cloud-init で "ノードの完成図" を 1 ファイルにする**

EC2 起動時に走る cloud-init で `containerd` install / `kubeadm` install / sysctl / module load まで済ませる。
**何度作っても同じ Node が立ち上がる** = Immutable Infrastructure。

> **痺れ所:** "手順書 (Runbook)" が **コード (cloud-init YAML)** に置き換わる瞬間。
> 「次の人にどう引き継ぐ?」の答えが **`terraform apply` の URL を渡すだけ** になる。

### 3. **AMI を data source で逃がす**

```hcl
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}
```

> AMI ID は region ごとに違うし、毎月更新される。**ハードコードしない** のが鉄則。

## 😱 あるある罠

- **`swap` が有効のまま**: kubelet が `--fail-swap-on=true` で起動しない。Ubuntu 24.04 は default で swap off だが念のため確認
- **`br_netfilter` モジュールを読み忘れ**: iptables が Pod 間トラフィックを見えなくなり Service が動かない
- **cgroup driver の不一致**: containerd と kubelet で `systemd` を揃える。混在すると Pod が一切動かない
- **SG の Inbound に `0.0.0.0/0:22`**: 世界中から SSH スキャンが来る。必ず自分の IP に絞る (`myip` data source)
- **public IP に頼って Node-to-Node 通信**: SG self-reference で **VPC 内通信を許可** するのが正解
- **t2.micro でやろうとする**: control-plane の memory が足りず kube-apiserver が OOM。**t3.medium 以上**

## やること

### 0. 準備

```bash
cd track-b-ec2-vanilla/01-terraform-vpc-ec2/terraform
```

`terraform.tfvars.example` を `terraform.tfvars` にコピーし、自分の値で埋める:

```hcl
region        = "us-east-1"
owner         = "alice"
ssh_public_key = "ssh-ed25519 AAAA... k8s-bootcamp"
my_ip_cidr    = "203.0.113.10/32"   # https://checkip.amazonaws.com/
```

### 1. Terraform ファイル一式

`versions.tf`:

```hcl
terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}
```

`variables.tf`:

```hcl
variable "region"          { type = string  default = "us-east-1" }
variable "owner"           { type = string }
variable "ssh_public_key"  { type = string }
variable "my_ip_cidr"      { type = string }
variable "vpc_cidr"        { type = string  default = "10.0.0.0/16" }
variable "instance_type"   { type = string  default = "t3.medium" }
variable "worker_count"    { type = number  default = 2 }
variable "k8s_version"     { type = string  default = "1.32" }   # 05 章で 1.33 へ上げる
```

`main.tf` (provider + AMI + key):

```hcl
provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project = "k8s-bootcamp"
      Track   = "B"
      Owner   = var.owner
    }
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

resource "aws_key_pair" "this" {
  key_name   = "k8s-bootcamp"
  public_key = var.ssh_public_key
}
```

`network.tf`:

```hcl
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "k8s-bootcamp" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "k8s-bootcamp" }
}

data "aws_availability_zones" "available" { state = "available" }

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 0)   # 10.0.0.0/24
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags = { Name = "k8s-bootcamp-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
```

`sg.tf`:

```hcl
resource "aws_security_group" "node" {
  name        = "k8s-bootcamp-node"
  description = "k8s nodes"
  vpc_id      = aws_vpc.this.id
}

# SSH from my IP
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.node.id
  cidr_ipv4         = var.my_ip_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

# kube-apiserver from my IP (kubectl) and VPC 内
resource "aws_vpc_security_group_ingress_rule" "api_from_me" {
  security_group_id = aws_security_group.node.id
  cidr_ipv4         = var.my_ip_cidr
  ip_protocol       = "tcp"
  from_port         = 6443
  to_port           = 6443
}

# self: Node 間通信は all-allow (学習用) 。本番は最小に
resource "aws_vpc_security_group_ingress_rule" "self_all" {
  security_group_id            = aws_security_group.node.id
  referenced_security_group_id = aws_security_group.node.id
  ip_protocol                  = "-1"
}

# NodePort from my IP
resource "aws_vpc_security_group_ingress_rule" "nodeport" {
  security_group_id = aws_security_group.node.id
  cidr_ipv4         = var.my_ip_cidr
  ip_protocol       = "tcp"
  from_port         = 30000
  to_port           = 32767
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.node.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
```

`ec2.tf`:

```hcl
locals {
  user_data = templatefile("${path.module}/../cloud-init/node.yaml.tftpl", {
    k8s_version = var.k8s_version
  })
}

resource "aws_instance" "cp" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.node.id]
  key_name                    = aws_key_pair.this.key_name
  associate_public_ip_address = true
  user_data                   = local.user_data
  root_block_device {
    volume_type = "gp3"
    volume_size = 30
  }
  tags = { Name = "k8s-bootcamp-cp", Role = "control-plane" }
}

resource "aws_instance" "worker" {
  count                       = var.worker_count
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.node.id]
  key_name                    = aws_key_pair.this.key_name
  associate_public_ip_address = true
  user_data                   = local.user_data
  root_block_device {
    volume_type = "gp3"
    volume_size = 30
  }
  tags = { Name = "k8s-bootcamp-worker-${count.index}", Role = "worker" }
}
```

`outputs.tf`:

```hcl
output "cp_public_ip"   { value = aws_instance.cp.public_ip }
output "cp_private_ip"  { value = aws_instance.cp.private_ip }
output "worker_public_ips"  { value = aws_instance.worker[*].public_ip }
output "worker_private_ips" { value = aws_instance.worker[*].private_ip }
output "ssh_cp" {
  value = "ssh -i ~/.ssh/k8s-bootcamp ubuntu@${aws_instance.cp.public_ip}"
}
```

### 2. cloud-init (containerd + kubeadm を冪等に)

`cloud-init/node.yaml.tftpl`:

```yaml
#cloud-config
write_files:
  - path: /etc/modules-load.d/k8s.conf
    content: |
      overlay
      br_netfilter
  - path: /etc/sysctl.d/99-k8s.conf
    content: |
      net.bridge.bridge-nf-call-iptables  = 1
      net.bridge.bridge-nf-call-ip6tables = 1
      net.ipv4.ip_forward                 = 1
runcmd:
  - swapoff -a
  - sed -i '/ swap / s/^/#/' /etc/fstab
  - modprobe overlay
  - modprobe br_netfilter
  - sysctl --system

  # containerd v2 (Ubuntu 24.04 のリポジトリ)
  - apt-get update
  - DEBIAN_FRONTEND=noninteractive apt-get install -y containerd ca-certificates curl gpg apt-transport-https
  - mkdir -p /etc/containerd
  - containerd config default | tee /etc/containerd/config.toml >/dev/null
  - sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  - systemctl restart containerd
  - systemctl enable containerd

  # kubeadm / kubelet / kubectl (pkgs.k8s.io)
  - mkdir -p -m 755 /etc/apt/keyrings
  - curl -fsSL https://pkgs.k8s.io/core:/stable:/v${k8s_version}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  - echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${k8s_version}/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
  - apt-get update
  - DEBIAN_FRONTEND=noninteractive apt-get install -y kubelet kubeadm kubectl
  - apt-mark hold kubelet kubeadm kubectl
  - systemctl enable kubelet
```

### 3. apply

> **AWS 料金注意:** ここから EC2 課金が始まります。**t3.medium × 3 + gp3 30GB × 3 ≒ $0.13/h** (us-east-1 オンデマンド)。寝る前に必ず `terraform destroy` か EC2 `stop`。

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

Outputs:

```
cp_public_ip        = "54.xxx.xxx.xxx"
worker_public_ips   = ["54.yyy.yyy.yyy", "54.zzz.zzz.zzz"]
ssh_cp              = "ssh -i ~/.ssh/k8s-bootcamp ubuntu@54.xxx.xxx.xxx"
```

### 4. cloud-init の完了を確認

cloud-init は EC2 起動後に数分走る。完了するまで待つ:

```bash
ssh -i ~/.ssh/k8s-bootcamp ubuntu@$(terraform output -raw cp_public_ip) \
  'cloud-init status --wait'
# status: done
```

### 5. ノードの "前提条件" を目で確認

control-plane に SSH して:

```bash
# cgroup v2
mount | grep cgroup2
# cgroup2 on /sys/fs/cgroup type cgroup2 ...

# swap off
swapon --show     # 何も出なければ OK
free -h           # Swap: 0B

# kernel module
lsmod | grep -E 'overlay|br_netfilter'

# sysctl
sysctl net.ipv4.ip_forward                    # = 1
sysctl net.bridge.bridge-nf-call-iptables     # = 1

# containerd
systemctl is-active containerd
crictl --runtime-endpoint unix:///run/containerd/containerd.sock version
# Version: ...  RuntimeVersion: v2.x ...

# kubelet (まだ起動はしない、kubeadm init で起動)
kubeadm version
kubelet --version
kubectl version --client
```

### 6. 後片付け (章をまたぐ時)

**続けて 02 章へ進む場合は destroy しない**。中断するなら:

```bash
# 一時退避: EC2 を stop (EBS 課金だけ残る)
aws ec2 stop-instances --instance-ids $(terraform output -json worker_public_ips ... )
# 完全削除
terraform destroy
```

## やってみて気づくこと

- k8s が動く Linux は **特別な OS ではない**。普通の Ubuntu に「カーネル設定 + cgroup v2 + containerd + kubelet」を載せただけ
- "クラスタを 1 台増やしたい" を実現する最短経路は **Terraform の `count` を +1 して `apply`**
- SG の中身が EKS の Security Group for Pods や Cilium の Policy と **同じ概念で繋がる** ことに気付く
- **AMI は data source、リージョンは変数、tag は default_tags** — この 3 つを守るだけで再利用性が劇的に上がる

## 参考
- AWS Provider: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- kubeadm Installing kubeadm: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
- containerd config: https://github.com/containerd/containerd/blob/main/docs/cri/config.md
- Ubuntu 24.04 AMI 検索: https://cloud-images.ubuntu.com/locator/ec2/
- cloud-init: https://cloudinit.readthedocs.io/
