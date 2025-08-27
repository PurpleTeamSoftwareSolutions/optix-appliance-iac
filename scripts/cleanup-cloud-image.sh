#!/usr/bin/env bash
set -e

echo "=== Starting aggressive cloud image cleanup ==="

echo "Modify the sudoers file"
chown root:root /tmp/sudoers
mv /tmp/sudoers /etc/sudoers

echo "Remove unnecessary packages for cloud image"
# Remove only safe packages, keep critical system components
apt-get purge -y \
    linux-firmware \
    linux-modules-extra-* \
    linux-headers-* \
    wireless-* \
    wpasupplicant \
    popularity-contest \
    installation-report \
    landscape-common \
    accountsservice \
    modemmanager \
    ppp \
    pppconfig \
    pppoeconf \
    ufw \
    apparmor \
    ubuntu-advantage-tools \
    ubuntu-release-upgrader-core \
    update-manager-core \
    snapd \
    lxd-agent-loader \
    cloud-guest-utils \
    sosreport \
    bcache-tools \
    btrfs-progs \
    ntfs-3g \
    xfsprogs \
    eject \
    pastebinit \
    byobu \
    || true

echo "Remove development packages (keep essential system packages)"
# Be selective about removing development packages
# Don't remove libc6-dev, libcrypt-dev, linux-libc-dev as they may be dependencies
apt-get purge -y \
    build-essential \
    gcc \
    g++ \
    make \
    || true

echo "Remove documentation and locales"
rm -rf /usr/share/doc/*
rm -rf /usr/share/man/*
rm -rf /usr/share/info/*
rm -rf /usr/share/lintian/*
rm -rf /usr/share/locale/*
find /var/cache/debconf -type f -name '*-old' -delete
rm -rf /var/lib/apt/lists/*

echo "Keep only essential locales"
# Ensure locales package is installed before using locale-gen
apt-get install -y locales || true
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen || true
echo "LANG=en_US.UTF-8" > /etc/default/locale

echo "Configure universal netplan config"
mkdir -p /etc/netplan
tee /etc/netplan/01-network.yaml > /dev/null <<EOF
network:
  version: 2
  ethernets:
    all-en:
      match:
        name: "en*"
      dhcp4: true
      dhcp6: true
EOF

find /etc/netplan -name "*.yaml" -not -name "01-network.yaml" -delete 2>/dev/null || true

echo "Clean package manager cache"
apt-get autoremove -y --purge
apt-get clean
apt-get autoclean
rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/apt/archives/*
rm -rf /var/cache/debconf/*
rm -rf /var/cache/apt/*.bin
dpkg --clear-avail

echo "Remove unnecessary kernel modules"
find /lib/modules -type f -name "*.ko" | while read -r module; do
    module_name=$(basename "$module" .ko)
    case "$module_name" in
        virtio*|ext4|xfs|overlay*|nls_*|crc*|libcrc*) ;;
        *) rm -f "$module" ;;
    esac
done

echo "Minimize systemd services"
systemctl disable \
    accounts-daemon.service \
    apparmor.service \
    apport.service \
    apt-daily-upgrade.timer \
    apt-daily.timer \
    motd-news.timer \
    fstrim.timer \
    e2scrub_all.timer \
    fwupd-refresh.timer \
    && true

echo "Clear logs and temporary files"
find /var/log -type f -exec truncate -s 0 {} \;
rm -rf /tmp/* /var/tmp/*
rm -rf /var/lib/dhcp/*
rm -rf /var/lib/cloud/*
rm -rf /var/log/journal/*

echo "Cleanup SSH host keys"
rm -f /etc/ssh/ssh_host_*

echo "Create SSH key regeneration service"
tee /etc/systemd/system/regenerate-ssh-keys.service > /dev/null <<EOF
[Unit]
Description=Regenerate SSH host keys
Before=ssh.service
ConditionPathExists=!/etc/ssh/ssh_host_ed25519_key

[Service]
Type=oneshot
ExecStart=/usr/bin/ssh-keygen -A

[Install]
WantedBy=multi-user.target
EOF

systemctl enable regenerate-ssh-keys.service

echo "Harden and minimize SSH configuration"
tee /etc/ssh/sshd_config > /dev/null <<EOF
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
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com
EOF

echo "Reset machine identification"
truncate -s 0 /etc/hostname
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id

echo "Clear bash history"
rm -f /root/.bash_history
rm -f /home/*/.bash_history
history -c

echo "Remove package lists"
rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/apt/*.bin

echo "Clear network leases"
rm -rf /var/lib/dhcp/*
rm -rf /var/lib/dhclient/*
rm -rf /var/lib/NetworkManager/*

echo "Remove cloud-init artifacts"
rm -rf /var/lib/cloud/*
rm -rf /var/log/cloud-init*

echo "Clear caches"
rm -rf /var/cache/fontconfig/*
rm -rf /var/cache/ldconfig/*
rm -rf /var/cache/man/*
rm -rf /var/cache/apparmor/*
rm -rf /var/cache/debconf/*

echo "Disable swap"
swapoff -a
sed -i '/swap/ s/^/#/' /etc/fstab

echo "Remove unnecessary firmware files"
rm -rf /lib/firmware/*

echo "Install GPG key and repo"
wget -O - https://apt.fury.io/purpleteamsoftware/gpg.key | gpg --dearmor -o /usr/share/keyrings/purpleteamsoftware-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/purpleteamsoftware-archive-keyring.gpg] https://apt.purpleteamsoftware.com/ /" | tee /etc/apt/sources.list.d/purpleteamsoftware.list

echo "Remove orphaned packages (if deborphan is available)"
# Only run if deborphan is installed
if command -v deborphan >/dev/null 2>&1; then
    deborphan --guess-all | xargs -r apt-get purge -y || true
fi

echo "Zero out free space for better compression"
dd if=/dev/zero of=/ZERO bs=1M || true
rm -f /ZERO

echo "Sync filesystem"
sync
sync
sync

echo "=== Cloud image cleanup complete ==="