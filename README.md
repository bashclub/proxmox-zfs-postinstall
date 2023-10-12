# proxmox-zfs-postinstall

This script installs and configures basic tools for running a Proxmox Server.
Following settings are made:
- Install and configure zfs-auto-snapshot
- Switch pve-enterprise/pve-no-subscription/pvetest repo
- Disable "No subscription message" in webinterface in no-subscription mode
- Add pve-enterprise subscription key
- Update system to the latest version
- Install common tools
- Install Proxmox SDN Extensions
- Configure automatic backup of /etc Folder
- Configure locales
- SSH server hardening
- Install checkzfs
- Install bashclub-zsync
- Create zfspool storage for swap disks if not exists
- Adjust default volblocksize for Proxmox zfspool storage
- Configure proxmox mail delivery with postfix
- Daily check (and download) for new stable virtio-win iso and prune old (unused) versions

# Usage

Just download and execute the script, all settings are made interactively.
```
wget -O ./postinstall --no-cache https://github.com/bashclub/proxmox-zfs-postinstall/raw/dev/postinstall
bash ./postinstall
```

# Author
### Thorsten Spille
[<img src="https://storage.ko-fi.com/cdn/brandasset/kofi_s_tag_dark.png" rel="Support me on Ko-Fi">](https://ko-fi.com/thorakel)
