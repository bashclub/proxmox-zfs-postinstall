# proxmox-zfs-postinstall

This script installs and configures basic tools for running a Proxmox Server.
Following settings are made:
- Disable `pve-enterprise` repo
- Add `pve-no-subscription` repo
- Upgrade system to latest version
- Install basic tools: `sudo vim ifupdown2 net-tools dnsutils ethtool git curl unzip screen iftop lshw smartmontools nvme-cli lsscsi sysstat zfs-auto-snapshot htop mc rpl`
- Configure snapshot retention for `zfs-auto-snapshot` interactively
- Calculates limits for level 1 arc (`zfs_arc_min` and `zfs_arc_max`) and asks you to apply or to input your preferences
- Configure backup of `/etc` folder to new zfs dataset on `rpool/pveconf`
