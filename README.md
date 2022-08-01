# Close orphaned ufw ports

This service will scan periodical for opened port in `ufw` that are orphaned, meaning no service is actually running on this port, and closes them.
You can edit the grace period for services to be detected under `/etc/close-orphaned-ufw-ports/config`.

Install on Debian 10:
```
sudo apt update && apt install ufw -y
git clone https://github.com/mietzen/close_orphaned_ufw_ports
sudo bash close_orphaned_ufw_ports/install.sh
```

Uninstall:
```
sudo bash close_orphaned_ufw_ports/uninstall.sh
```