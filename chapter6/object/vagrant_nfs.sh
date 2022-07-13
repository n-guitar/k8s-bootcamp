sudo apt-get install -y nfs-kernel-server
sudo mkdir /nfsshare
sudo mkdir /nfsshare/pv
sudo mkdir /nfsshare/storageclass

cat <<EOF | sudo tee -a /etc/exports
/nfsshare *(rw,fsid=0,async,no_subtree_check,no_auth_nlm,insecure,no_root_squash)
EOF

sudo systemctl restart nfs-server
