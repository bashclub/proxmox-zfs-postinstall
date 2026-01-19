# proxmox-zfs-postinstall

This script installs and configures essential and advanced tools for a new Proxmox Server (Version 8+), with ZFS storage. All settings are made interactively via Dialog/Whiptail.

> [!IMPORTANT]  
> Please download the updated version of this script and re-run, if your Proxmox WebUI doesn't show up after update to 8.4.5 or 9.0.0 beta

## Features
- Configure ZFS ARC Cache (optimizes RAM usage for ZFS)
- Configure vm.swappiness (kernel swap behavior)
- Install and configure zfs-auto-snapshot (automatic ZFS snapshots, individually configurable)
- Switch between pve-enterprise, pve-no-subscription, pvetest repositories
- Switch Ceph repo between quincy/reef and enterprise/no-subscription/test or remove it
- Add pve-enterprise subscription key (optional)
- Update system to the latest version
- Install common tools (curl, git, htop, etc.)
- Install Proxmox SDN Extensions
- Configure automatic backup of /etc folder (ZFS + cron)
- Configure locales (language and region settings)
- SSH server hardening (new host keys, restrictive algorithms, disable root login with password)
- Install checkzfs
- Install bashclub-zsync
- Install virtio-win ISO (including automatic cleanup of old versions)
- Create zfspool storage for swap disks if not exists
- Adjust default volblocksize for Proxmox zfspool storages
- Configure Proxmox mail delivery and notifications (SMTP, Auth, TLS/StartTLS)
- Remove old virtio-win-updater
- Set content of proxmox storage "local" (remove ability to save backups)
- Enable autotrim on all supported ZFS pools
- Enable autoexpand on all ZFS pools

## Workflow
- The script guides you step by step through all important configurations.
- All settings are queried interactively and can be customized.
- After the summary, all selected options are automatically applied.

## Requirements
- Proxmox VE 8.x (tested with Bookworm)
- Root privileges required
- Internet connection for package installation

# Usage

Just download and execute the script, all settings are made interactively.
```
wget -O ./postinstall --no-cache https://github.com/bashclub/proxmox-zfs-postinstall/raw/main/postinstall
bash ./postinstall
```

# Author
### Thorsten Spille
[<img src="https://storage.ko-fi.com/cdn/brandasset/kofi_s_tag_dark.png" rel="Support me on Ko-Fi">](https://ko-fi.com/thorakel)
