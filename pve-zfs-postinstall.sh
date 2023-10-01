#!/bin/bash
#
# This script configures basic settings and install standard tools on your Proxmox VE Server with ZFS storage
# 
# Features:
# - Configure ZFS ARC Cache
# - Configure vm.swappiness
# - Install and configure zfs-auto-snapshot
# - Switch pve-enterprise/pve-no-subscription repo
# - Disable "No subscription message" in webinterface in no-subscription mode
# - Update system to the latest version
# - Install common tools
# - Install Proxmox SDN Extensions
# - Configure automatic backup of /etc Folder
# - Configure locales
# - SSH server hardening
# - Configure proxmox mail delivery with postfix
# - Adjust default volblocksize for Proxmox zfspool storages
# - Create zfspool storage for swap disks if not exists
#
#
# Author: (C) 2023 Thorsten Spille <thorsten@bashclub.org>

set -uo pipefail

#### INITIAL VARIABLES ####
PROG=$(basename "$0")

# Required tools for usage in postinstall
REQUIRED_TOOLS="curl ifupdown2 git gron libsasl2-modules lsb-release libpve-network-perl postfix ssl-cert zfs-auto-snapshot"

# Optional tools to install
OPTIONAL_TOOLS="dnsutils ethtool htop iftop jq lshw lsscsi mc net-tools nvme-cli rpl screen smartmontools sudo sysstat tmux unzip vim"

# Settings for Backup of /etc folder
PVE_CONF_BACKUP_TARGET=rpool/pveconf
PVE_CONF_BACKUP_CRON_TIMER="3,18,33,48 * * * *"

# Round factor to set L1ARC cache (Megabytes)
ROUND_FACTOR=512

# get total size of all zpools
ZPOOL_SIZE_SUM_BYTES=0
for line in $(zpool list -o size -Hp); do ZPOOL_SIZE_SUM_BYTES=$(($ZPOOL_SIZE_SUM_BYTES+$line)); done

# get information about available ram
MEM_TOTAL_BYTES=$(($(awk '/MemTotal/ {print $2}' /proc/meminfo) * 1024))

# get values if defaults are set
ARC_MAX_DEFAULT_BYTES=$(($MEM_TOTAL_BYTES / 2))
ARC_MIN_DEFAULT_BYTES=$(($MEM_TOTAL_BYTES / 32))

# get current settings
ARC_MIN_CUR_BYTES=$(cat /sys/module/zfs/parameters/zfs_arc_min)
ARC_MAX_CUR_BYTES=$(cat /sys/module/zfs/parameters/zfs_arc_max)

# get vm.swappiness
SWAPPINESS=$(cat /proc/sys/vm/swappiness)

# zfs-auto-snapshot default values
declare -A auto_snap_keep=( ["frequent"]="12" ["hourly"]="96" ["daily"]="14" ["weekly"]="6" ["monthly"]="3" )

#### FUNCTIONS ####

roundup(){
    echo $(((($1 + $ROUND_FACTOR) / $ROUND_FACTOR) * $ROUND_FACTOR))
}

roundoff(){
    echo $((($1 / $ROUND_FACTOR) * $ROUND_FACTOR))
}

isnumber(){
    re='^[0-9]+$'
    if ! [[ $1 =~ $re ]] ; then
        return 1
    else
        return 0
    fi
}

inputbox_int(){
    cancel=0
    while true; do
        if ! out=$(whiptail --title "$1" --backtitle "$PROG" --inputbox "$2" $3 76 $4 3>&1 1>&2 2>&3) ; then
            cancel=1 ; break 
        fi
        if isnumber $out; then
            break
        fi
    done
    echo $out
    return $cancel
}

cancel_dialog() {
    whiptail --title "CANCEL POSTINSTALL" --backtitle $PROG --msgbox "Postinstall was cancelled by user interaction" 8 76 3>&1 1>&2 2>&3
    exit 127
}

arc_suggestion(){

    ZFS_ARC_MIN_MEGABYTES=$(roundoff $(($ZPOOL_SIZE_SUM_BYTES / 2048 / 1024 / 1024)))
    ZFS_ARC_MAX_MEGABYTES=$(roundup $(($ZPOOL_SIZE_SUM_BYTES / 1024 / 1024 / 1024)))

    if [ $ARC_MIN_DEFAULT_BYTES -lt 33554432 ]; then ARC_MIN_DEFAULT_MB="32" ; else ARC_MIN_DEFAULT_MB="$(($ARC_MIN_DEFAULT_BYTES / 1024 / 1024))" ; fi
    if [ $ARC_MIN_CUR_BYTES -gt 0 ]; then ARC_MIN_CURRENT_MB="$(($ARC_MIN_CUR_BYTES / 1024 / 1024))" ; else ARC_MIN_CURRENT_MB="0" ; fi
    if [ $ARC_MAX_CUR_BYTES -gt 0 ]; then ARC_MAX_CURRENT_MB="$(($ARC_MAX_CUR_BYTES / 1024 / 1024))" ; else ARC_MAX_CURRENT_MB="0" ; fi

    if ! whiptail --title "CONFIGURE ZFS L1ARC SIZE" \
    --backtitle $PROG \
    --yes-button "Accept" \
    --no-button "Edit" \
    --yesno " Summary: \n \
    System Memory: $(($MEM_TOTAL_BYTES / 1024 / 1024)) MB\n \
    Zpool size (sum): $(($ZPOOL_SIZE_SUM_BYTES / 1024 / 1024)) MB\n \
\n \
Note: zfs_arc_min must always be lower than zfs_arc_max! \n\n \
The L1ARC cache suggestion is calculated by size of all zpools \n\n \
Suggested values: \n \
    zfs_arc_min: $(($ZFS_ARC_MIN_MEGABYTES)) MB (default: $ARC_MIN_DEFAULT_MB MB, current: $ARC_MIN_CURRENT_MB MB)\n \
    zfs_arc_max: $(($ZFS_ARC_MAX_MEGABYTES)) MB (default: $(($ARC_MAX_DEFAULT_BYTES / 1024 / 1024)) MB, current: $ARC_MAX_CURRENT_MB MB)\n" 17 76; then
        arc_set_manual
    fi
}

arc_set_manual() {
    if ! ZFS_ARC_MIN_MEGABYTES=$(inputbox_int 'CONFIGURE ZFS L1ARC MIN SIZE' 'Please enter zfs_arc_min in MB' 7 $ZFS_ARC_MIN_MEGABYTES) ; then cancel_dialog ; fi
    if ! ZFS_ARC_MAX_MEGABYTES=$(inputbox_int 'CONFIGURE ZFS L1ARC MAX SIZE' 'Please enter zfs_arc_max in MB' 7 $ZFS_ARC_MAX_MEGABYTES) ; then cancel_dialog ; fi
}

vm_swappiness () {
    if ! SWAPPINESS=$(inputbox_int "CONFIGURE SWAPPINESS" "Please enter percentage of free RAM to start swapping" 8 $SWAPPINESS) ; then cancel_dialog ; fi
}

auto_snapshot(){
    if dpkg -l zfs-auto-snapshot > /dev/null 2>&1 ; then
        for interval in "${!auto_snap_keep[@]}"; do
            if [[ "$interval" == "frequent" ]]; then
                auto_snap_keep[$interval]=$(cat /etc/cron.d/zfs-auto-snapshot | grep keep | cut -d' ' -f19 | cut -d '=' -f2)
            else
                auto_snap_keep[$interval]=$(cat /etc/cron.$interval/zfs-auto-snapshot | grep keep | cut -d' ' -f6 | cut -d'=' -f2)
            fi
        done
    fi
    for interval in "${!auto_snap_keep[@]}"; do
        if ! auto_snap_keep[$interval]=$(inputbox_int "CONFIGURE ZFS-AUTO-SNAPSHOT" "Please set number of $interval snapshots to keep" 7 ${auto_snap_keep[$interval]}) ; then cancel_dialog ; fi
    done
}

check_subscription(){
    serverid=$(pvesh get nodes/px1/subscription --output-format yaml | grep serverid | cut -d' ' -f2)
    sub_status=$(pvesh get nodes/px1/subscription --output-format yaml | grep status | cut -d' ' -f2)
    if [[ $sub_status == "notfound" ]]; then
        if [[ $repo_selection == "pve-enterprise" ]]; then
            if whiptail --title "NO PROXMOX SUBSCRIPTION FOUND" \
            --backtitle $PROG \
            --yes-button "ADD" \
            --no-button "SKIP" \
            --yesno "Server ID: $serverid\nDo you want to add a subscription key?" 17 76 ; then
                add_subscription
            fi
        else
            if whiptail --title "NO PROXMOX SUBSCRIPTION FOUND" \
            --backtitle $PROG \
            --yes-button "SUPPRESS WARNING" \
            --no-button "SKIP" \
            --yesno "Do you want to suppress the no subscription warning in WebGUI?" 17 76 ; then
                suppress_no_subscription_warning
            fi
        fi
    fi
}

add_subscription(){

}

suppress_no_subscription_warning(){

}

select_pve_repos(){
    pveenterprise=OFF
    pvenosubscription=OFF
    pvetest=OFF
    if [ -f /etc/apt/sources.list.d/pve-enterprise.list ]; then
        if $(grep -v '#' /etc/apt/sources.list.d/pve-enterprise.list | grep "pve-enterprise") ; then
            pveenterprise=ON
        else
            if [ -f /etc/apt/sources.list ]; then
                if $(grep -v '#' /etc/apt/sources.list | grep "pve-no-subscription") ; then
                    pvenosubscription=ON
                elif $(grep -v '#' /etc/apt/sources.list | grep "pvetest") ; then
                    pvetest=ON
                else
                    pveenterprise=ON
                fi 
            fi
        fi
    fi
    repo_selection=$(whiptail --title "SELECT PVE REPOSITORY" --backtitle "$PROG" \
    --radiolist "Choose Proxmox VE repository" 20 76 4 \
    "pve-enterprise" "Proxmox VE Enterprise repository" "$pveenterprise" \
    "pve-no-subscription" "Proxmox VE No Subscription repository" "$pvenosubscription" \
    "pvetest" "Proxmox VE Testing repository" "$pvetest" 3>&1 1>&2 2>&3)


}

source /etc/os-release

# Calculate and suggest values for ZFS L1ARC cache
arc_suggestion

# Set swapping behaviour
vm_swappiness

# Configure count per interval of zfs-auto-snapshot
auto_snapshot

# Select proxmox repository
select_pve_repos

# subscription related actions
select_subscription