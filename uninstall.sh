#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

systemctl stop close-orphaned-ufw-ports.service
systemctl disable close-orphaned-ufw-ports.service

rm -rf /dev/shm/close-orphaned-ufw-ports.*
rm -rf /etc/close-orphaned-ufw-ports
rm -rf /usr/bin/close-orphaned-ufw-ports
rm -rf /etc/systemd/system/close-orphaned-ufw-ports.service

exit 0
