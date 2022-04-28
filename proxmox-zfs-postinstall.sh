#!/bin/bash

###### CONFIG SECTION ######

# Define basic tools to install
TOOLS="sudo vim ifupdown2 libpve-network-perl net-tools dnsutils ethtool git curl unzip screen iftop lshw smartmontools nvme-cli lsscsi sysstat zfs-auto-snapshot htop mc rpl lsb-release"

#### PVE CONF BACKUP CONFIGURATION ####

# Define target dataset for backup of /etc
# IMPORTANT NOTE: Don't type in the leading /, this will be set where needed
PVE_CONF_BACKUP_TARGET=rpool/pveconf

# Define timer for your backup cronjob (default: every 15 minutes fron 3 through 59)
PVE_CONF_BACKUP_CRON_TIMER="3,18,33,48 * * * *"

# Get Debian version info
source /etc/os-release

###### SYSTEM INFO AND INTERACTIVE CONFIGURATION SECTION ######

ROUND_FACTOR=512

roundup(){
    echo $(((($1 + $ROUND_FACTOR) / $ROUND_FACTOR) * $ROUND_FACTOR))
}

roundoff(){
    echo $((($1 / $ROUND_FACTOR) * $ROUND_FACTOR))
}

#### L1ARC SIZE CONFIGURATION ####

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

# calculate suggested l1arc sice
ZFS_ARC_MIN_MEGABYTES=$(roundup $(($ZPOOL_SIZE_SUM_BYTES / 2048 / 1024 / 1024)))
ZFS_ARC_MAX_MEGABYTES=$(roundoff $(($ZPOOL_SIZE_SUM_BYTES / 1024 / 1024 / 1024)))

echo -e "######## CONFIGURE ZFS L1ARC SIZE ########\n"
echo "System Summary:"
echo -e "\tSystem Memory:\t\t$(($MEM_TOTAL_BYTES / 1024 / 1024))\tMB"
echo -e "\tZpool size (sum):\t$(($ZPOOL_SIZE_SUM_BYTES / 1024 / 1024))\tMB"
echo -e "Calculated l1arc if set to defaults:"
if [ $ARC_MIN_DEFAULT_BYTES -lt 33554432 ]; then
    echo -e "\tDefault zfs_arc_min:\t32\tMB"
else
    echo -e "\tDefault zfs_arc_min:\t$(($ARC_MIN_DEFAULT_BYTES / 1024 / 1024))\tMB"
fi
echo -e "\tDefault zfs_arc_max:\t$(($ARC_MAX_DEFAULT_BYTES / 1024 / 1024))\tMB"
echo -e "Current l1arc configuration:"
if [ $ARC_MIN_CUR_BYTES -gt 0 ]; then
    echo -e "\tCurrent zfs_arc_min:\t$(($ARC_MIN_CUR_BYTES / 1024 / 1024))\tMB"
else
    echo -e "\tCurrent zfs_arc_min:\t0"
fi
if [ $ARC_MAX_CUR_BYTES -gt 0 ]; then
    echo -e "\tCurrent zfs_arc_max:\t$(($ARC_MAX_CUR_BYTES / 1024 / 1024))\tMB"
else
    echo -e "\tCurrent zfs_arc_max:\t0"
fi
echo -e "Note: If your current values are 0, the calculated values above will apply."
echo ""
echo -e "The l1arc cache will be set relative to the size (sum) of your zpools by policy"
echo -e "zfs_arc_min:\t\t\t$(($ZFS_ARC_MIN_MEGABYTES))\tMB\t\t= 512 MB RAM per 1 TB ZFS storage (round off in 512 MB steps)"
echo -e "zfs_arc_max:\t\t\t$(($ZFS_ARC_MAX_MEGABYTES))\tMB\t\t= 1 GB RAM per 1 TB ZFS storage (round up in 512 MB steps)"
echo ""
RESULT=not_set
while [ "$(echo $RESULT | awk '{print tolower($0)}')" != "y" ] && [ "$(echo $RESULT | awk '{print tolower($0)}')" != "n" ] && [ "$(echo $RESULT | awk '{print tolower($0)}')" != "" ]; do
    read -p "If you want to apply the values by script policy type 'y', type 'n' to adjust the values yourself [Y/n]? "
    RESULT=${REPLY}
done
if [[ "$(echo $RESULT | awk '{print tolower($0)}')" == "n" ]]; then
    read -p "Please type in the desired value in MB for 'zfs_arc_min' [$(($ZFS_ARC_MIN_MEGABYTES))]: "
    if [[ ${REPLY} -gt 0 ]]; then
        ZFS_ARC_MIN_MEGABYTES=$((${REPLY}))
    fi
    read -p "Please type in the desired value in MB for 'zfs_arc_max' [$(($ZFS_ARC_MAX_MEGABYTES))]: "
    if [[ ${REPLY} -gt 0 ]]; then
        ZFS_ARC_MAX_MEGABYTES=$((${REPLY}))
    fi
fi

#### SWAPPINESS ####

echo -e "######## CONFIGURE SWAPPINESS ########\n"
SWAPPINESS=$(cat /proc/sys/vm/swappiness)
echo "The current swappiness is configured to '$SWAPPINESS %' of free memory until using swap."
read -p "If you want to change the swappiness, please type in the percentage as number (0 = diasbled):" user_input
if echo "$user_input" | grep -qE '^[0-9]+$'; then
    echo "Changing swappiness from '$SWAPPINESS %' to '$user_input %'"
    SWAPPINESS=$user_input
else
    echo "No input - swappiness unchanged at '$SWAPPINESS %'."
fi

#### ZFS AUTO SNAPSHOT CONFIGURATION ####

# get information about zfs-auto-snapshot and ask for snapshot retention
declare -A auto_snap_keep=( ["frequent"]="8" ["hourly"]="48" ["daily"]="31" ["weekly"]="8" ["monthly"]="3" )
dpkg -l zfs-auto-snapshot > /dev/null

if [ $? -eq 0 ]; then
    echo "'zfs-auto-snapshot' already installed. Reading config..."
    for interval in "${!auto_snap_keep[@]}"; do
        if [[ "$interval" == "frequent" ]]; then
            auto_snap_keep[$interval]=$(cat /etc/cron.d/zfs-auto-snapshot | grep keep | cut -d' ' -f19 | cut -d '=' -f2)
        else
            auto_snap_keep[$interval]=$(cat /etc/cron.$interval/zfs-auto-snapshot | grep keep | cut -d' ' -f6 | cut -d'=' -f2)
        fi
    done
else
    echo "'zfs-auto-snapshot' not installed yet, using script defaults..."
fi
echo -e "######## CONFIGURE ZFS AUTO SNAPSHOT ########\n"
for interval in "${!auto_snap_keep[@]}"; do
    read -p "Please set how many $interval snapshots to keep (current: keep=${auto_snap_keep[$interval]})" user_input
    if echo "$user_input" | grep -qE '^[0-9]+$'; then
        echo "Changing $interval from ${auto_snap_keep[$interval]} to $user_input"
        auto_snap_keep[$interval]=$user_input
    else
        echo "No input - $interval unchanged at ${auto_snap_keep[$interval]}."
    fi
done

#### CHECKMK AGENT CONFIGURATION ####
read -p "Do you want to install checkmk agent of this machine? [y/N] " install_checkmk
if [[ "$install_checkmk" == "y" ]]; then
    read -p "Please specify the base url to your checkmk server (e.g. https://check.zmb.rocks/bashclub): " cmk_agent_url
    read -p "Enable agent encryption (requires setup of Agent Encryption on your checkmk instance). Do you want to activate agent encryption? [y/N] " cmk_encrypt
    if [[ "$cmk_encrypt" == "y" ]]; then
        read -p "Please enter the encryption passphrase: " cmk_enc_pass
    fi
    read -p "Register your machine on your checkmk server (requires preconfigured automation secret)? [y/N] " cmk_register
    if [[ "$cmk_register" == "y" ]]; then
        read -p "Please enter your automation secret: " cmk_secret
        read -p "Please enter the folder where to store the host: " cmk_folder
        cmk_site=$(echo $cmk_agent_url | cut -d'/' -f4)
        read -p "Please enter the checkmk site name: [$cmk_site]" user_input
        if [[ $(echo -n "$user_input") != "" ]]; then
            cmk_site=$user_input
        fi
        echo "Please select which agent ip address to register:"
        select ip in $(ip a | grep "inet " | cut -d ' ' -f6 | cut -d/ -f1); do
            cmk_reg_ip=$ip
            break
        done
    fi
fi


###### INSTALLER SECTION ######

# disable pve-enterprise repo and add pve-no-subscription repo
if [[ "$(uname -r)" == *"-pve" ]]; then
    echo "Deactivating pve-enterprise repository"
    mv /etc/apt/sources.list.d/pve-enterprise.list /etc/apt/sources.list.d/pve-enterprise.list.bak > /dev/null 2>&1
    echo "Activating pve-no-subscription repository"
    q=$(cat /etc/apt/sources.list | grep "pve-no-subscription")
    if [ $? -gt 0 ]; then
        echo "deb http://download.proxmox.com/debian/pve $VERSION_CODENAME pve-no-subscription" >> /etc/apt/sources.list
    fi
    rm -f /etc/apt/sources.list.d/pve-no-subscription.list
fi
echo "Getting latest package lists"
apt update > /dev/null 2>&1

# include interfaces.d to enable SDN features
q=$(cat /etc/network/interfaces | grep "source /etc/network/interfaces.d/*")
if [ $? -gt 0 ]; then
    echo "source /etc/network/interfaces.d/*" >> /etc/network/interfaces
fi

# update system and install basic tools
echo "Upgrading system to latest version - Depending on your version this could take a while..."
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt -y -qq dist-upgrade > /dev/null 2>&1
echo "Installing toolset - Depending on your version this could take a while..."
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt -y -qq install $TOOLS > /dev/null 2>&1

# configure zfs-auto-snapshot
for interval in "${!auto_snap_keep[@]}"; do
    echo "Setting zfs-auto-snapshot retention: $interval = ${auto_snap_keep[$interval]}"
    if [[ "$interval" == "frequent" ]]; then
        CURRENT=$(cat /etc/cron.d/zfs-auto-snapshot | grep keep | cut -d' ' -f19 | cut -d '=' -f2)
        if [[ "${auto_snap_keep[$interval]}" != "$CURRENT" ]]; then
            rpl "keep=$CURRENT" "keep=${auto_snap_keep[$interval]}" /etc/cron.d/zfs-auto-snapshot > /dev/null 2>&1
        fi
    else
        CURRENT=$(cat /etc/cron.$interval/zfs-auto-snapshot | grep keep | cut -d' ' -f6 | cut -d'=' -f2)
        if [[ "${auto_snap_keep[$interval]}" != "$CURRENT" ]]; then
            rpl "keep=$CURRENT" "keep=${auto_snap_keep[$interval]}" /etc/cron.$interval/zfs-auto-snapshot > /dev/null 2>&1
        fi
    fi
done

echo "Configuring swappiness"
echo "vm.swappiness=$SWAPPINESS" > /etc/sysctl.d/swappiness.conf
sysctl -w vm.swappiness=$SWAPPINESS

echo "Configuring pve-conf-backup"
# create backup jobs of /etc
zfs list $PVE_CONF_BACKUP_TARGET > /dev/null 2>&1
if [ $? -ne 0 ]; then
    zfs create $PVE_CONF_BACKUP_TARGET
fi

if [[ "$(df -h -t zfs | grep /$ | cut -d ' ' -f1)" == "rpool/ROOT/pve-1" ]] ; then
  echo "$PVE_CONF_BACKUP_CRON_TIMER root rsync -va --delete /etc /$PVE_CONF_BACKUP_TARGET > /$PVE_CONF_BACKUP_TARGET/pve-conf-backup.log" > /etc/cron.d/pve-conf-backup
fi

ZFS_ARC_MIN_BYTES=$((ZFS_ARC_MIN_MEGABYTES * 1024 *1024))
ZFS_ARC_MAX_BYTES=$((ZFS_ARC_MAX_MEGABYTES * 1024 *1024))

echo "Adjusting ZFS level 1 arc"
echo $ZFS_ARC_MIN_BYTES > /sys/module/zfs/parameters/zfs_arc_min
echo $ZFS_ARC_MAX_BYTES > /sys/module/zfs/parameters/zfs_arc_max

cat << EOF > /etc/modprobe.d/zfs.conf
options zfs zfs_arc_min=$ZFS_ARC_MIN_BYTES
options zfs zfs_arc_max=$ZFS_ARC_MAX_BYTES
EOF

if [[ "$install_checkmk" == "y" ]]; then
    echo "Installing checkmk agent..."
    if [[ $( echo -n "$(openssl s_client -connect $(echo $cmk_agent_url | cut -d'/' -f3):443  <<< "Q" 2>/dev/null | grep "Verify return code" | cut -d ' ' -f4)" ) -gt 0 ]]; then
        wget_opts="--no-check-certificate"
        curl_opts="--insecure"
    fi
    wget -q -O /usr/local/bin/check_mk_agent $wget_opts $cmk_agent_url/check_mk/agents/check_mk_agent.linux
    wget -q -O /usr/local/bin/mk-job $wget_opts $cmk_agent_url/check_mk/agents/mk-job
    wget -q -O /usr/local/bin/check_mk_caching_agent  $wget_opts $cmk_agent_url/check_mk/agents/check_mk_caching_agent.linux
    wget -q -O /usr/local/bin/waitmax  $wget_opts $cmk_agent_url/check_mk/agents/waitmax
    chmod +x /usr/local/bin/check_mk_agent
    chmod +x /usr/local/bin/mk-job
    chmod +x /usr/local/bin/check_mk_caching_agent
    chmod +x /usr/local/bin/waitmax
    /usr/local/bin/check_mk_agent > /dev/null
    wget -q -O /etc/systemd/system/check_mk.socket $wget_opts $cmk_agent_url/check_mk/agents/cfg_examples/systemd/check_mk.socket
    cat << EOF > /etc/systemd/system/check_mk@.service
# systemd service definition file
[Unit]
Description=Check_MK

[Service]
# "-" path prefix makes systemd record the exit code,
# but the unit is not set to failed.
ExecStart=-/usr/local/bin/check_mk_agent
Type=forking

User=root
Group=root

StandardInput=socket
EOF

    mkdir -p /etc/check_mk
    if [[ "$cmk_encrypt" == "y" ]]; then
        mkdir -p /etc/check_mk
        cat << EOF > /etc/check_mk/encryption.cfg
ENCRYPTED=yes
PASSPHRASE='$cmk_enc_pass'
EOF
    chmod 600 /etc/check_mk/encryption.cfg
    fi

    mkdir -p /var/lib/check_mk_agent
    mkdir -p /var/lib/check_mk_agent/spool
    mkdir -p /var/lib/check_mk_agent/job
    mkdir -p /usr/lib/check_mk_agent/local
    mkdir -p /usr/lib/check_mk_agent/plugins
    wget -q -O /usr/lib/check_mk_agent/plugins/smart $wget_opts $cmk_agent_url/check_mk/agents/plugins/smart
    chmod +x /usr/lib/check_mk_agent/plugins/smart
    wget -q -O /usr/lib/check_mk_agent/plugins/mk_inventory $wget_opts $cmk_agent_url/check_mk/agents/plugins/mk_inventory.linux
    chmod +x /usr/lib/check_mk_agent/plugins/mk_inventory
    wget -q -O /usr/lib/check_mk_agent/plugins/mk_apt $wget_opts $cmk_agent_url/check_mk/agents/plugins/mk_apt
    chmod +x /usr/lib/check_mk_agent/plugins/mk_apt
    #LocalDirectory: /usr/lib/check_mk_agent/local
    systemctl daemon-reload
    systemctl enable check_mk.socket
    systemctl restart sockets.target

    if [[ "$cmk_register" == "y" ]]; then
        cmk_request="request={\"hostname\":\"$(echo -n $(hostname -f))\",\"folder\":\"$cmk_folder\",\"attributes\":{\"ipaddress\":\"$cmk_reg_ip\",\"site\":\"$cmk_site\",\"tag_agent\":\"cmk-agent\"},\"create_folders\":\"1\"}"
        curl $curl_opts "$cmk_agent_url/check_mk/webapi.py?action=add_host&_secret=$cmk_secret&_username=automation" -d $cmk_request
        curl $curl_opts "$cmk_agent_url/check_mk/webapi.py?action=activate_changes&_secret=$cmk_secret&_username=automation" -d "request={\"sites\":[\"$cmk_site\"],\"allow_foreign_changes\":\"0\"}"
    fi
fi

echo "Updating initramfs - This will take some time..."
update-initramfs -u -k all > /dev/null 2>&1

echo "Proxmox postinstallation finished!"
