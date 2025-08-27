#!/usr/bin/env bash
set -e

echo "=== Starting aggressive cloud image cleanup ==="

echo "Modify the sudoers file"
chown root:root /tmp/sudoers
mv /tmp/sudoers /etc/sudoers

echo "Remove unnecessary packages for cloud image"
# Aggressively remove packages not needed for minimal cloud operation
apt-get purge -y \
    linux-firmware \
    linux-modules-extra-* \
    linux-headers-* \
    linux-source-* \
    linux-tools-* \
    linux-cloud-tools-* \
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
    iptables \
    apparmor \
    ubuntu-advantage-tools \
    ubuntu-release-upgrader-core \
    update-manager-core \
    update-notifier-common \
    snapd \
    lxd* \
    lxcfs \
    lxd-agent-loader \
    cloud-guest-utils \
    sosreport \
    bcache-tools \
    btrfs-progs \
    cryptsetup* \
    dmsetup \
    hdparm \
    lvm2 \
    mdadm \
    multipath-tools \
    ntfs-3g \
    xfsprogs \
    eject \
    pastebinit \
    byobu \
    tmux \
    screen \
    vim-common \
    vim-runtime \
    nano \
    command-not-found* \
    friendly-recovery \
    dosfstools \
    || true

echo "Remove development packages and interpreters"
# Remove all development tools and unnecessary interpreters
apt-get purge -y \
    build-essential \
    gcc* \
    g++* \
    make \
    cmake \
    autoconf \
    automake \
    flex \
    bison \
    python3-pip \
    python3-dev \
    python3-setuptools \
    python3-wheel \
    perl \
    perl-base \
    perl-modules-* \
    || true

echo "Remove language runtimes not essential for system"
apt-get purge -y \
    ruby* \
    nodejs* \
    || true

echo "Remove documentation, locales, and unnecessary files"
rm -rf /usr/share/doc/*
rm -rf /usr/share/man/*
rm -rf /usr/share/info/*
rm -rf /usr/share/lintian/*
rm -rf /usr/share/linda/*
rm -rf /usr/share/bug/*
rm -rf /usr/share/groff/*
rm -rf /usr/share/perl5/*
rm -rf /usr/share/pixmaps/*
rm -rf /usr/share/sounds/*
rm -rf /usr/share/icons/*
rm -rf /usr/share/mime/*
rm -rf /usr/share/fonts/*
rm -rf /usr/share/X11/*
rm -rf /usr/share/gnome/*
rm -rf /usr/share/kde*
rm -rf /usr/share/themes/*
rm -rf /usr/share/backgrounds/*
rm -rf /usr/share/wallpapers/*
# Keep only en_US locale
find /usr/share/locale -mindepth 1 -maxdepth 1 -type d ! -name 'en*' -exec rm -rf {} \;
find /usr/share/i18n/locales -type f ! -name 'en_*' ! -name 'C' ! -name 'POSIX' -delete 2>/dev/null || true
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
# Keep only essential modules for cloud/virtual environments
find /lib/modules -type f -name "*.ko" | while read -r module; do
    module_name=$(basename "$module" .ko)
    case "$module_name" in
        # Keep essential modules
        virtio*|ext4|ext3|ext2|overlay*|nls_utf8|crc32*|libcrc32*) ;;
        e1000*|vmxnet*|hv_*|xen*) ;;
        sd_mod|sr_mod|sg|scsi_mod|libata|ahci) ;;
        # Remove everything else
        *) rm -f "$module" ;;
    esac
done

# Remove entire categories of modules
rm -rf /lib/modules/*/kernel/sound
rm -rf /lib/modules/*/kernel/drivers/gpu
rm -rf /lib/modules/*/kernel/drivers/media
rm -rf /lib/modules/*/kernel/drivers/bluetooth
rm -rf /lib/modules/*/kernel/drivers/wireless
rm -rf /lib/modules/*/kernel/drivers/staging
rm -rf /lib/modules/*/kernel/drivers/infiniband
rm -rf /lib/modules/*/kernel/drivers/isdn
rm -rf /lib/modules/*/kernel/drivers/input/joystick
rm -rf /lib/modules/*/kernel/drivers/input/tablet
rm -rf /lib/modules/*/kernel/drivers/usb/serial

# Regenerate module dependencies
for kernel in /lib/modules/*; do
    [ -d "$kernel" ] && depmod -a "$(basename "$kernel")" 2>/dev/null || true
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

echo "Clear all caches and unnecessary libraries"
rm -rf /var/cache/*
mkdir -p /var/cache/apt/archives/partial

echo "Remove unnecessary libraries"
# Remove X11 libraries
find /usr/lib -name 'libX*' -delete 2>/dev/null || true
find /usr/lib -name 'libgtk*' -delete 2>/dev/null || true
find /usr/lib -name 'libQt*' -delete 2>/dev/null || true

# Remove Python cache
find / -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
find / -type f -name '*.pyc' -delete 2>/dev/null || true
find / -type f -name '*.pyo' -delete 2>/dev/null || true

# Remove package manager cache but keep structure
rm -rf /var/cache/apt/*.bin
rm -rf /var/cache/apt/archives/*
rm -rf /var/cache/debconf/*-old

echo "Disable swap"
swapoff -a
sed -i '/swap/ s/^/#/' /etc/fstab

echo "Remove all firmware files"
rm -rf /lib/firmware/*
rm -rf /usr/lib/firmware/*

echo "Install GPG key and repo"
wget -O - https://apt.fury.io/purpleteamsoftware/gpg.key | gpg --dearmor -o /usr/share/keyrings/purpleteamsoftware-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/purpleteamsoftware-archive-keyring.gpg] https://apt.purpleteamsoftware.com/ /" | tee /etc/apt/sources.list.d/purpleteamsoftware.list

echo "Remove orphaned packages (if deborphan is available)"
# Only run if deborphan is installed
if command -v deborphan >/dev/null 2>&1; then
    deborphan --guess-all | xargs -r apt-get purge -y || true
fi

echo "Strip unnecessary sections from binaries"
find /usr/bin /usr/sbin /bin /sbin -type f -exec strip --strip-all {} \; 2>/dev/null || true
find /usr/lib /lib -name '*.so*' -type f -exec strip --strip-unneeded {} \; 2>/dev/null || true

echo "Remove duplicate files and create hardlinks"
apt-get install -y hardlink || true
hardlink -c /usr /lib || true
apt-get purge -y hardlink || true

echo "Zero out and remove swap"
swapoff -a || true
rm -f /swapfile || true
rm -f /swap.img || true

echo "Final cleanup of package database"
rm -rf /var/lib/dpkg/*-old
rm -rf /var/lib/dpkg/info/*.list
rm -rf /var/lib/dpkg/info/*.md5sums
rm -rf /var/lib/dpkg/info/*.preinst
rm -rf /var/lib/dpkg/info/*.postinst
rm -rf /var/lib/dpkg/info/*.prerm
rm -rf /var/lib/dpkg/info/*.postrm

echo "Zero out free space for better compression"
# Write zeros to all free space
dd if=/dev/zero of=/ZERO bs=4M || true
rm -f /ZERO
# Do it for /boot too if separate
[ -d /boot ] && dd if=/dev/zero of=/boot/ZERO bs=4M 2>/dev/null || true
[ -f /boot/ZERO ] && rm -f /boot/ZERO

echo "Sync filesystem"
sync
sync
sync

echo "=== Cloud image cleanup complete ==="