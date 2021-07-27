# proxmox-zfs-postinstall

This script installs and configures basic tools for running a Proxmox Server.
Following settings are made:
- Disable `pve-enterprise` repo
- Add `pve-no-subscription` repo
- Upgrade system to latest version
- Install basic tools: `sudo vim ifupdown2 net-tools dnsutils ethtool git curl unzip screen iftop lshw smartmontools nvme-cli lsscsi sysstat zfs-auto-snapshot htop mc rpl`
- Configure snapshot retention for `zfs-auto-snapshot` interactively
- `zfs_arc_[min|max]` will be calculated by size sum of all zpools in 512 MB steps
- Configure backup of `/etc` folder to new zfs dataset on `rpool/pveconf`
- Configure `vm.swappiness` interactively
- Install checkmk Agent with optional encryption and registration
- Added Support for Proxmox VE 7.0

# Usage

Just download and execute the script, all settings are made interactively.
```
wget https://github.com/bashclub/proxmox-zfs-postinstall/raw/main/proxmox-zfs-postinstall.sh
bash ./proxmox-zfs-postinstall.sh
```
