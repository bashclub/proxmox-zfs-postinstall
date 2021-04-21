# proxmox-zfs-postinstall

This script installs and configures basic tools for running a Proxmox Server.
Following settings are made:
- Remove `pve-enterprise` repo
- Add `pve-no-subscription` repo
- Upgrade system to latest version
- Install basic tools: `vim ifupdown2 net-tools dnsutils ethtool git curl unzip screen iftop lshw smartmontools nvme-cli lsscsi sysstat zfs-auto-snapshot`
- Configure snapshot retention for `zfs-auto-snapshot`
- Set limits for level 1 arc (`zfs_arc_min` and `zfs_arc_max`)
