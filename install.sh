#!/bin/bash

###### CONFIG SECTION ######

# Define basic tools to install
TOOLS="sudo vim ifupdown2 net-tools dnsutils ethtool git curl unzip screen iftop lshw smartmontools nvme-cli lsscsi sysstat zfs-auto-snapshot htop mc rpl"

# Define target dataset for backup of /etc
# IMPORTANT NOTE: Don't type in the leading /, this will be set where needed
PVE_CONF_BACKUP_TARGET=rpool/pveconf

# Define timer for your backup cronjob (default: every 15 minutes)
PVE_CONF_BACKUP_CRON_TIMER="*/15 * * * *"

###### SYSTEM INFO AND INTERACTIVE CONFIGURATION SECTION ######

#### L1ARC SIZE CONFIGURATION ####

# get total size of all zpools
ZPOOL_SIZE_SUM_BYTES=0
zpool list -o size -Hp | while read size_per_pool; do
    ZPOOL_SIZE_SUM_BYTES=$(($ZPOOL_SIZE_SUM_BYTES + $size_per_pool))
done

# get information about available ram
MEM_TOTAL_BYTES=$(free -tb | tail -1 | cut -d ' ' -f3)

# get values if defaults are set
ARC_MAX_DEFAULT_BYTES=$((MEM_TOTAL / 2))
ARC_MIN_DEFAULT_BYTES=$((MEM_TOTAL / 32))

# get current settings
ARC_MIN_SET_BYTES=$(cat /sys/module/zfs/parameters/zfs_arc_min)
ARC_MAX_SET_BYTES=$(cat /sys/module/zfs/parameters/zfs_arc_max)

# calculate suggested l1arc sice
ZFS_ARC_MIN_BYTES=$(($ZPOOL_SIZE_SUM_BYTES / 4096))
ZFS_ARC_MAX_BYTES=$(($ZPOOL_SIZE_SUM_BYTES / 1024))

echo -e "######## CONFIGURE ZFS L1ARC SIZE ########\n"
echo "System Summary:"
echo -e "\tSystem Memory:\t$(($MEM_TOTAL_BYTES / 1024 / 1024)) MB"
echo -e "\tZpool size (sum):\t$(($ZPOOL_SIZE_SUM_BYTES / 1024 / 1024)) MB"
echo -e "Calculated l1arc if set to defaults:"
if [ $ARC_MIN_DEFAULT_BYTES -lt 33554432 ]; then
    echo -e "\tDefault zfs_arc_min:\t32 MB"
else
    echo -e "\tDefault zfs_arc_min:\t$(($ARC_MIN_DEFAULT_BYTES / 1024 / 1024)) MB"
fi
echo -e "\tDefault zfs_arc_max:\t$(($ARC_MAX_DEFAULT_BYTES / 1024 / 1024)) MB"
echo -e "Current l1arc configuration:"
if [ $ARC_MIN_SET_BYTES > 0]; then
    echo -e "\tCurrent zfs_arc_min:\t$(($ARC_MIN_SET_BYTES / 1024 / 1024)) MB"
else
    echo -e "\tCurrent zfs_arc_min:\t0"
fi
if [ $ARC_MAX_SET_BYTES > 0]; then
    echo -e "\tCurrent zfs_arc_max:\t$(($ARC_MAX_SET_BYTES / 1024 / 1024)) MB"
else
    echo -e "\tCurrent zfs_arc_max:\t0"
fi
echo -e "Note: If your current values are 0, the calculated values above will apply."
echo ""
echo "The l1arc cache will be set relative to the size (sum) of your zpools by the policy 'zfs_arc_min = 256 MB / 1 TB' and 'zfs_arc_max = 1 GB / 1 TB'"
echo "zfs_arc_min=\t$(($ZFS_ARC_MIN_BYTES / 1024 / 1024)) MB"
echo "zfs_arc_max=\t$(($ZFS_ARC_MAX_BYTES / 1024 / 1024)) MB"
echo ""
RESULT=not_set
while [[ "$(echo $RESULT | awk '{print tolower($0)}')" != "y" ]] && [[ "$(echo $RESULT | awk '{print tolower($0)}')" != "n"]]; do
    echo "You can now adjust the l1arc values. Change settings [y/N]?"
    read
    RESULT=${REPLY}
done
if [[ "$(echo $RESULT | awk '{print tolower($0)}')" == "y" ]]; then
    echo "Please type in the desired value in MB for 'zfs_arc_min' [$(($ZFS_ARC_MIN_BYTES / 1024 / 1024))]:"
    read
    if [[ ${REPLY} -gt 0 ]]; then
        $ZFS_ARC_MIN_BYTES=$((${REPLY} * 1024 * 1024))
    fi
    echo "Please type in the desired value in MB for 'zfs_arc_max' [$(($ZFS_ARC_MAX_BYTES / 1024 / 1024))]:"
    read
    if [[ ${REPLY} -gt 0 ]]; then
        $ZFS_ARC_MAX_BYTES=$((${REPLY} * 1024 * 1024))
    fi
fi

#### ZFS AUTO SNAPSHOT CONFIGURATION ####

# get information about zfs-auto-snapshot and ask for snapshot retention
dpkg -l zfs-auto-snapshot
declare -A auto_snap_keep
if [ $1 -ne 0 ]; then
    auto_snap_keep["frequent"]=8 ; auto_snap_keep["hourly"]=48 ; auto_snap_keep["daily"]=31 ; auto_snap_keep["weekly"]=8 ; auto_snap_keep["monthly"]=3
else
    for interval in "${auto_snap_keep[@]}"; do
        if [[ "$interval" == "frequent" ]]; then
            auto_snap_keep["$interval"]=$(cat /etc/cron.d/zfs-auto-snapshot | grep keep | cut -d' ' -f19 | cut -d '=' -f2)
        else
            auto_snap_keep["$interval"]=$(cat /etc/cron.$interval/zfs-auto-snapshot | grep keep | cut -d' ' -f6 | cut -d'=' -f2)
        fi
    done
fi
echo -e "######## CONFIGURE ZFS AUTO SNAPSHOT ########\n"
for interval in "${auto_snap_keep[@]}"; do
    echo "Please set how many $interval snapshots to keep (current: keep=${auto_snap_keep[$interval]})"
    read
    if [ "${auto_snap_keep[$interval]}" != "${REPLY}" ]; then
        auto_snap_keep["$interval"]=${REPLY}
    fi
done

###### INSTALLER SECTION ######

# disable pve-enterprise repo and add pve-no-subscription repo
mv /etc/apt/sources.list.d/pve-enterprise.list /etc/apt/sources.list.d/pve-enterprise.list.bak
echo "deb http://download.proxmox.com/debian/pve buster pve-no-subscription" > /etc/apt/sources.list.d/pve-no-subscription.list
apt update

# update system and install basic tools
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt -y -qq dist-upgrade
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt -y -qq install $TOOLS

# configure zfs-auto-snapshot
for interval in "${auto_snap_keep[@]}"; do
    if [[ "$interval" == "frequent" ]]; then
        CURRENT=$(cat /etc/cron.d/zfs-auto-snapshot | grep keep | cut -d' ' -f19 | cut -d '=' -f2)
        if [[ "${auto_snap_keep[$interval]}" != "$CURRENT" ]]; then
            rpl "keep=$CURRENT" "keep=${auto_snap_keep[$interval]}" /etc/cron.d/zfs-auto-snapshot
        fi
    else
        CURRENT=$(cat /etc/cron.$interval/zfs-auto-snapshot | grep keep | cut -d' ' -f6 | cut -d'=' -f2)
        if [[ "${auto_snap_keep[$interval]}" != "$CURRENT"]]; then
            rpl "keep=$CURRENT" "keep=${auto_snap_keep[$interval]}" /etc/cron.$interval/zfs-auto-snapshot
        fi
    fi
done

echo $ZFS_ARC_MIN_BYTES > /sys/module/zfs/parameters/zfs_arc_min
echo $ZFS_ARC_MAX_BYTES > /sys/module/zfs/parameters/zfs_arc_max

cat << EOF > /etc/modprobe.d/zfs.conf
options zfs zfs_arc_min=$ZFS_ARC_MIN_BYTES
options zfs zfs_arc_min=$ZFS_ARC_MAX_BYTES
EOF
update-initramfs -u -k all

# create backup jobs of /etc
zfs list $PVE_CONF_BACKUP_TARGET

if [ $? -ne 0 ]
    zfs create $PVE_CONF_BACKUP_TARGET
fi

echo "$PVE_CONF_BACKUP_CRON_TIMER root rsync -vhab --delete /etc /$PVE_CONF_BACKUP_TARGET > /$PVE_CONF_BACKUP_TARGET/pve-conf-backup.log" > /etc/cron.d/pve-conf-backup