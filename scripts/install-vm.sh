#!/bin/bash

# VM deployment script with IP injection and VNC support
# Usage: ./deploy-vm.sh <vm-name> <ip-address> <gateway> <dns>

VM_NAME="$1"
IP_ADDRESS="$2"
GATEWAY="${3:-192.168.1.1}"
DNS="${4:-8.8.8.8}"
TEMPLATE_IMAGE="/var/lib/libvirt/images/optix-appliance-1749581169.qcow2"
VM_IMAGE="/kvm/scanners/${VM_NAME}.qcow2"

# Validate arguments
if [[ -z "$VM_NAME" || -z "$IP_ADDRESS" ]]; then
    echo "Usage: $0 <vm-name> <ip-address> [gateway] [dns]"
    echo "Example: $0 optix-prod-01 192.168.1.100 192.168.1.1 8.8.8.8"
    exit 1
fi

# Create VM disk from template
echo "Creating VM disk for $VM_NAME..."
sudo qemu-img create -f qcow2 -F qcow2 -b "$TEMPLATE_IMAGE" "$VM_IMAGE" 150G


# Inject static IP
virt-customize -a /kvm/scanners/"${VM_NAME}".qcow2 \
  --run-command "mkdir -p /etc/netplan" \
  --run-command "cat > /etc/netplan/01-network.yaml <<EOF
network:
  version: 2
  ethernets:
    all-en:
      match:
        name: \"en*\"
      dhcp4: false
      addresses: [${IP_ADDRESS}]
      gateway4: ${GATEWAY}
      nameservers:
        addresses: [${DNS}]
EOF" \
  --run-command "echo ${VM_NAME} > /etc/hostname" \
  --run-command "hostnamectl set-hostname ${VM_NAME}" \
  --run-command "netplan generate"

# Deploy VM
echo "Deploying VM $VM_NAME with IP $IP_ADDRESS..."
sudo virt-install \
    --name "$VM_NAME" \
    --memory 16384 \
    --vcpus 4 \
    --disk path="$VM_IMAGE",bus=virtio \
    --network type=direct,source=bond1.2,source_mode=bridge,model=virtio \
    --os-variant ubuntu24.04 \
    --graphics vnc,listen=0.0.0.0,port=-1 \
    --video virtio \
    --import \
    --noautoconsole

# Cleanup temp files
rm -f /tmp/user-data-"${VM_NAME}" /tmp/meta-data-"${VM_NAME}"
sudo rm -f /kvm/scanners/"${VM_NAME}"-cidata.iso

echo "VM $VM_NAME deployed successfully!"
echo "IP: $IP_ADDRESS"
echo "You can connect via: ssh ubuntu@$IP_ADDRESS"
echo "VNC console available through Cockpit or virsh console"