#!/bin/bash

# Define basic tools to install
TOOLS="vim ifupdown2 net-tools dnsutils ethtool git curl unzip screen iftop lshw smartmontools nvme-cli lsscsi sysstat zfs-auto-snapshot htop mc rpl"

# Define zfs-auto-snapshot retention policy
SNAP_FREQUENT=8
SNAP_HOURLY=48
SNAP_DAILY=31
SNAP_WEEKLY=8
SNAP_MONTHLY=3

# Define zfs arcsize in Megabytes (MB)
ZFS_ARC_MIN=128
ZFS_ARC_MAX=256

# disable pve-enterprise repo and add pve-no-subscription repo
mv /etc/apt/sources.list.d/pve-enterprise.list /etc/apt/sources.list.d/pve-enterprise.list.bak
echo "deb http://download.proxmox.com/debian/pve buster pve-no-subscription" > /etc/apt/sources.list.d/pve-no-subscription.list
apt update

# update system and install basic tools
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt -y -qq dist-upgrade
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt -y -qq install $TOOLS

# configure zfs-auto-snapshot
rpl "keep=4" "keep=$SNAP_FREQUENT" /etc/cron.d/zfs-auto-snapshot
rpl "keep=24" "keep=$SNAP_HOURLY" /etc/cron.hourly/zfs-auto-snapshot
rpl "keep=31" "keep=$SNAP_DAILY" /etc/cron.hourly/zfs-auto-snapshot
rpl "keep=8" "keep=$SNAP_WEEKLY" /etc/cron.weekly/zfs-auto-snapshot
rpl "keep=8" "keep=$SNAP_MONTHLY" /etc/cron.monthly/zfs-auto-snapshot

# set zfs_arc_limits
ZFS_ARC_MIN_BYTES=$(($ZFS_ARC_MIN*1024*1024))
ZFS_ARC_MAX_BYTES=$(($ZFS_ARC_MAX*1024*1024))

echo $ZFS_ARC_MIN_BYTES > /sys/module/zfs/parameters/zfs_arc_min
echo $ZFS_ARC_MAX_BYTES > /sys/module/zfs/parameters/zfs_arc_max

cat << EOF > /etc/modprobe.d/zfs.conf
options zfs zfs_arc_min=$ZFS_ARC_MIN_BYTES
options zfs zfs_arc_min=$ZFS_ARC_MAX_BYTES
EOF
update-initramfs -u -k all
