#!/bin/bash

# VM deployment script with IP injection
# Usage: ./deploy-vm.sh <vm-name> <ip-address> <gateway> <dns>

VM_NAME="$1"
IP_ADDRESS="$2"
GATEWAY="${3:-192.168.1.1}"
DNS="${4:-8.8.8.8}"
TEMPLATE_IMAGE="/var/lib/libvirt/images/optix-appliance.qcow2"
VM_IMAGE="/var/lib/libvirt/images/${VM_NAME}.qcow2"

# Validate arguments
if [[ -z "$VM_NAME" || -z "$IP_ADDRESS" ]]; then
    echo "Usage: $0 <vm-name> <ip-address> [gateway] [dns]"
    echo "Example: $0 optix-prod-01 192.168.1.100 192.168.1.1 8.8.8.8"
    exit 1
fi

# Create VM disk from template
echo "Creating VM disk for $VM_NAME..."
sudo qemu-img create -f qcow2 -F qcow2 -b "$TEMPLATE_IMAGE" "$VM_IMAGE" 150G

# Create cloud-init user-data
cat > /tmp/user-data-${VM_NAME} << EOF
#cloud-config
hostname: ${VM_NAME}
manage_etc_hosts: true

# Network configuration
write_files:
  - path: /etc/netplan/50-cloud-init.yaml
    content: |
      network:
        version: 2
        ethernets:
          all-en:
            match:
              name: "en*"
            dhcp4: false
            addresses: [${IP_ADDRESS}/24]
            gateway4: ${GATEWAY}
            nameservers:
              addresses: [${DNS}]
    permissions: '0644'

# Run commands on first boot
runcmd:
  - netplan apply
  - systemctl restart networking
  - hostnamectl set-hostname ${VM_NAME}

# Final message
final_message: "VM ${VM_NAME} is ready with IP ${IP_ADDRESS}"
EOF

# Create cloud-init meta-data
cat > /tmp/meta-data-${VM_NAME} << EOF
instance-id: ${VM_NAME}
local-hostname: ${VM_NAME}
EOF

# Create cloud-init ISO
echo "Creating cloud-init configuration..."
sudo genisoimage -output /var/lib/libvirt/images/${VM_NAME}-cidata.iso \
    -volid cidata -joliet -rock \
    /tmp/user-data-${VM_NAME} /tmp/meta-data-${VM_NAME}

# Deploy VM
echo "Deploying VM $VM_NAME with IP $IP_ADDRESS..."
sudo virt-install \
    --name "$VM_NAME" \
    --memory 16384 \
    --vcpus 4 \
    --disk path="$VM_IMAGE",bus=virtio \
    --disk path="/var/lib/libvirt/images/${VM_NAME}-cidata.iso",device=cdrom \
    --network type=direct,source=bond1.10,source_mode=bridge,model=virtio \
    --os-variant ubuntu24.04 \
    --import \
    --noautoconsole

# Cleanup temp files
rm -f /tmp/user-data-${VM_NAME} /tmp/meta-data-${VM_NAME}

echo "VM $VM_NAME deployed successfully!"
echo "IP: $IP_ADDRESS"
echo "You can connect via: ssh ubuntu@$IP_ADDRESS"