#!/usr/bin/env bash
#===============================================================================
#
#          FILE: rescan_scsi_device.sh
# 
#         USAGE: ./rescan_scsi_device.sh 
# 
#   DESCRIPTION: 批量执行扫描 SCSI 总线
# 
#  ORGANIZATION: dqzboy.com
#       CREATED: 2021
#===============================================================================

echo
cat << EOF
██████╗  ██████╗ ███████╗██████╗  ██████╗ ██╗   ██╗            ██████╗ ██████╗ ███╗   ███╗
██╔══██╗██╔═══██╗╚══███╔╝██╔══██╗██╔═══██╗╚██╗ ██╔╝           ██╔════╝██╔═══██╗████╗ ████║
██║  ██║██║   ██║  ███╔╝ ██████╔╝██║   ██║ ╚████╔╝            ██║     ██║   ██║██╔████╔██║
██║  ██║██║▄▄ ██║ ███╔╝  ██╔══██╗██║   ██║  ╚██╔╝             ██║     ██║   ██║██║╚██╔╝██║
██████╔╝╚██████╔╝███████╗██████╔╝╚██████╔╝   ██║       ██╗    ╚██████╗╚██████╔╝██║ ╚═╝ ██║
╚═════╝  ╚══▀▀═╝ ╚══════╝╚═════╝  ╚═════╝    ╚═╝       ╚═╝     ╚═════╝ ╚═════╝ ╚═╝     ╚═╝
                                                                                          
EOF

# 重新扫描SCSI设备
function rescan_scsi_device() {
    echo "Rescanning SCSI device for $1..."
    echo 1 > "/sys/class/scsi_device/$1/device/rescan"
}

# 获取 SCSI 设备列表
scsi_devices=$(ls /sys/class/scsi_device/)

# 遍历每个 SCSI 设备并重新扫描
for device in $scsi_devices; do
    rescan_scsi_device $device
done

echo "SCSI device rescan complete!"
