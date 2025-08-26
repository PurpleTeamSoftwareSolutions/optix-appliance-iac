#!/bin/bash -e

wget -O - https://apt.fury.io/purpleteamsoftware/gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/purpleteamsoftware-archive-keyring.gpg
sudo chown root:root /tmp/sudoers
sudo mv /tmp/sudoers /etc/sudoers
sudo mv /tmp/purpleteamsoftware.list /etc/apt/sources.list.d/
sudo apt update && sudo apt dist-upgrade -y
sudo apt install open-vm-tools -y
sudo rm -rf /home/ubuntu/.ssh/authorized_keys
sudo rm -rf /root/.ssh/authorized_keys
