#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

mkdir -p /etc/close-orphaned-ufw-ports
touch /etc/close-orphaned-ufw-ports/whitelist
cp ./config /etc/close-orphaned-ufw-ports/config
chmod 744 /etc/close-orphaned-ufw-ports/config
chmod 744 /etc/close-orphaned-ufw-ports/whitelist

cp ./close-orphaned-ufw-ports.sh /usr/bin/close-orphaned-ufw-ports
chmod +x /usr/bin/close-orphaned-ufw-ports

cp ./close-orphaned-ufw-ports.service /etc/systemd/system/close-orphaned-ufw-ports.service

systemctl enable close-orphaned-ufw-ports.service

echo "You can Whitelist Ports that should stay open, even if no service is running"
echo "under /etc/close-orphaned-ufw-ports/whitelist"
echo "Adding your SSH Port (e.g. 22) would be a good idea"
echo "Start the service with:"
echo "sudo systemctl start close-orphaned-ufw-ports.service"
exit 0
