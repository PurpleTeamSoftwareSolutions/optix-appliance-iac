#!/bin/bash -e

sudo rpm --import https://apt.fury.io/purpleteamsoftware/gpg.key
sudo chown root:root /tmp/sudoers
sudo mv /tmp/sudoers /etc/sudoers

cat <<'EOF' | sudo tee /etc/yum.repos.d/purpleteamsoftware.repo
[purpleteamsoftware]
name=PurpleTeam Software Repository
baseurl=https://yum.fury.io/purpleteamsoftware/
enabled=1
gpgcheck=1
gpgkey=https://apt.fury.io/purpleteamsoftware/gpg.key
EOF

sudo dnf update -y
sudo dnf install open-vm-tools -y
sudo rm -rf /home/ec2-user/.ssh/authorized_keys
sudo rm -rf /root/.ssh/authorized_keys