#!/usr/bin/env bash

echo "Modify the sudoers file"
sudo chown root:root /tmp/sudoers
sudo mv /tmp/sudoers /etc/sudoers

echo "Stop services for cleanup"
sudo systemctl stop rsyslog || true

echo "Clear audit logs"
[[ -f /var/log/audit/audit.log ]] && sudo truncate -s 0 /var/log/audit/audit.log
[[ -f /var/log/wtmp ]] && sudo truncate -s 0 /var/log/wtmp
[[ -f /var/log/lastlog ]] && sudo truncate -s 0 /var/log/lastlog

echo "Cleanup persistent udev rules"
sudo rm -f /etc/udev/rules.d/70-persistent-net.rules

echo "Remove netplan override (leave to cloud-init)"
sudo rm -f /etc/netplan/01-network.yaml

echo "Cleanup /tmp and /var/tmp"
sudo rm -rf /tmp/*
sudo rm -rf /var/tmp/*

echo "Harden SSH configuration"
sudo tee /etc/ssh/sshd_config > /dev/null <<EOF
Protocol 2
Port 22
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
UsePAM yes
X11Forwarding no
PrintMotd no
TCPKeepAlive yes
ClientAliveInterval 300
ClientAliveCountMax 2
MaxAuthTries 3
MaxStartups 2
LoginGraceTime 30
KexAlgorithms diffie-hellman-group14-sha256,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group-exchange-sha256,curve25519-sha256,sntrup761x25519-sha512@openssh.com,curve25519-sha256@libssh.org
Ciphers aes128-ctr,aes192-ctr,aes256-ctr,aes128-gcm@openssh.com,aes256-gcm@openssh.com,chacha20-poly1305@openssh.com
MACs hmac-sha2-256,hmac-sha2-512,umac-128@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,umac-128-etm@openssh.com
HostKeyAlgorithms ssh-ed25519-cert-v01@openssh.com,ssh-rsa-cert-v01@openssh.com,ssh-ed25519,ssh-rsa
EOF

echo "Cleanup SSH host keys"
sudo rm -f /etc/ssh/ssh_host_*

echo "Ensure SSH keys regenerate on boot"
sudo tee /etc/rc.local > /dev/null <<EOF
#!/bin/bash
test -f /etc/ssh/ssh_host_ed25519_key || dpkg-reconfigure openssh-server
exit 0
EOF
sudo chmod +x /etc/rc.local

echo "Reset hostname (cloud-init will set)"
sudo truncate -s 0 /etc/hostname

echo "Clean apt cache"
sudo apt clean

echo "Install GPG key and repo"
wget -O - https://apt.fury.io/purpleteamsoftware/gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/purpleteamsoftware-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/purpleteamsoftware-archive-keyring.gpg] https://apt.purpleteamsoftware.com/ /" | sudo tee /etc/apt/sources.list.d/purpleteamsoftware.list

echo "Disable swap and host aliases"
sudo sed -i '/swap/ s/^/#/' /etc/fstab
sudo sed -i '/127\.0\.1\.1/ s/^/#/' /etc/hosts

echo "Extend disk volume"
sudo lvextend -l +100%FREE /dev/mapper/ubuntu--vg-ubuntu--lv
sudo resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv

echo "Force NoCloud datasource for cloud-init"
sudo tee /etc/cloud/cloud.cfg.d/99_nocloud.cfg > /dev/null <<EOF
datasource_list: [ NoCloud ]
EOF

echo "Clean cloud-init state"
sudo cloud-init clean --logs

echo "Cleanup complete."
