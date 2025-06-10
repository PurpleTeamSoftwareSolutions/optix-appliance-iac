#!/usr/bin/env bash

echo "Modify the sudoers file"
sudo chown root:root /tmp/sudoers
sudo mv /tmp/sudoers /etc/sudoers

echo "Stop services for cleanup"
#Stop services for cleanup
sudo service rsyslog stop

echo "clear audit logs"
#clear audit logs
if [[ -f /var/log/audit/audit.log ]]; then
    sudo sh -c "cat /dev/null > /var/log/audit/audit.log"
fi
if [[ -f /var/log/wtmp ]]; then
    sudo sh -c "cat /dev/null > /var/log/wtmp"
fi
if [[ -f /var/log/lastlog ]]; then
    sudo sh -c "cat /dev/null > /var/log/lastlog"
fi

echo "cleanup persistent udev rules"
#cleanup persistent udev rules
if [[ -f /etc/udev/rules.d/70-persistent-net.rules ]]; then
    sudo rm /etc/udev/rules.d/70-persistent-net.rules
fi

echo "configure universal netplan config"
#configure universal netplan config for cross-platform compatibility
sudo mkdir -p /etc/netplan
sudo tee /etc/netplan/01-network.yaml > /dev/null <<EOF
network:
  version: 2
  ethernets:
    all-en:
      match:
        name: "en*"
      dhcp4: true
EOF

sudo find /etc/netplan -name "*.yaml" -not -name "01-network.yaml" -delete 2>/dev/null || true

echo "cleanup /tmp directories"
#cleanup /tmp directories
sudo rm -rf /tmp/*
sudo rm -rf /var/tmp/*

echo "harden ssh configuration"
#harden ssh configuration
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

echo "cleanup current ssh keys"
#cleanup current ssh keys
sudo rm -f /etc/ssh/ssh_host_*

echo "regenerate on boot"
#regenerate on boot
sudo sh -c 'echo "#! /bin/bash" > /etc/rc.local'
sudo sh -c 'echo "test -f /etc/ssh/ssh_host_ed25519_key || dpkg-reconfigure openssh-server" >> /etc/rc.local'
sudo sh -c 'echo "exit 0" >> /etc/rc.local'
sudo chmod +x /etc/rc.local

echo "reset hostname"
#reset hostname
sudo sh -c "cat /dev/null > /etc/hostname"

echo "cleanup apt"
#cleanup apt
sudo apt clean

wget -O - https://apt.fury.io/purpleteamsoftware/gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/purpleteamsoftware-archive-keyring.gpg
sudo echo "deb [signed-by=/usr/share/keyrings/purpleteamsoftware-archive-keyring.gpg] https://apt.purpleteamsoftware.com/ /" | sudo tee -a /etc/apt/sources.list.d/purpleteamsoftware.list

sudo sed -i '/swap/ s/^/#/' /etc/fstab
sudo sed -i '/127\.0\.1\.1/ s/^/#/' /etc/hosts

echo "extend the drive"
sudo lvextend -l +100%FREE /dev/mapper/ubuntu--vg-ubuntu--lv
sudo resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv