# WARNING: This script will delete ufw rules / close ports. Only use it if you understand how it works. Don't blame me if you mess things up.
# Close orphaned ufw ports

This service will scan periodical for opened port in `ufw` that are orphaned, meaning no service is actually running on this port, and closes them.
You can edit the grace period for services to be redetected under `/etc/close-orphaned-ufw-ports/config`.
and whitelist ports under: `/etc/close-orphaned-ufw-ports/whitelist.{v4,v6}`

Install on Debian:
```
sudo apt update && apt install ufw -y
git clone https://github.com/mietzen/close-orphaned-ufw-ports
cd close-orphaned-ufw-ports
sudo bash install.sh
```

Uninstall:
```
sudo bash uninstall.sh
```