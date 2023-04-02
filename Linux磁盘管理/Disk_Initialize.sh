#!/bin/bash

#===============================================================================
#
#          FILE: Disk_Initialize.sh
# 
#         USAGE: ./Disk_Initialize.sh 
# 
#   DESCRIPTION: Linux CentOS Disk免交互格式化分区、挂载
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

# 安装软件
EXPECT=`yum list installed | grep -w expect`
if [ $? -eq 0 ];then
   echo
   echo
   echo "--------------------------------------------------------------------------"
   echo "               Yum Install expect Skip..."
   echo "--------------------------------------------------------------------------"
   echo
   echo
else 
   yum -y install expect
   echo
   echo
   echo "--------------------------------------------------------------------------"
   echo "               Yum Install expect Done..."
   echo "--------------------------------------------------------------------------"
   echo
   echo
fi

# 解锁文件
chattr -i /etc/fstab

OS_CN() {
# 注意修改磁盘名称前缀,例如这里的 /sd
Dsk=`lsblk -r --output NAME,MOUNTPOINT | awk -F \/ '/sd/ { dsk=substr($1,1,3);dsks[dsk]+=1 } END { for ( i in dsks ) { if (dsks[i]==1) print i } }'`
Disk="/dev/${Dsk}"
DiskP="${Disk}1"
if [ ! -z "${Dsk}" ];then
expect -c "
  spawn fdisk ${Disk}
  expect {
    -re \"(.*)三思(.*)(\n*)(.*)获取帮助(.*)\" { send \"n\r\";exp_continue }
    \"default p\" { send \"\r\";exp_continue }
    \"分区号\" { send \"\r\";exp_continue }
    \"起始 扇区\" { send \"\r\";exp_continue }
    \"Last 扇区\" { send \"\r\";exp_continue }
    \"命令\" { send \"wq\r\";exp_continue }
  }
"
else
   echo
   echo
   echo "--------------------------------------------------------------------------"
   echo "               The new disk was not found. Exit..."
   echo "--------------------------------------------------------------------------"
   echo
   exit 1
fi
}

OS_EN() {
Dsk=`lsblk -r --output NAME,MOUNTPOINT | awk -F \/ '/sd/ { dsk=substr($1,1,3);dsks[dsk]+=1 } END { for ( i in dsks ) { if (dsks[i]==1) print i } }'`
Disk="/dev/${Dsk}"
DiskP="${Disk}1"
if [ ! -z "${Dsk}" ];then
expect -c "
  spawn fdisk ${Disk}
  expect {
    -re \"(.*)careful(.*)(\n*)(.*)help(.*)\" { send \"n\r\";exp_continue }
    \"default p\" { send \"\r\";exp_continue }
    \"Partition number\" { send \"\r\";exp_continue }
    \"First sector\" { send \"\r\";exp_continue }
    \"Last sector\" {send \"\r\";exp_continue }
    \"Command\" { send \"wq\r\";exp_continue }
  }
"
else
   echo
   echo
   echo "--------------------------------------------------------------------------"
   echo "              The new disk was not found. Exit..."
   echo "--------------------------------------------------------------------------"
   echo
   exit 1
fi
}

Mkfs_Disk() {
sleep 3

# 格式化分区
Partitions=`blkid | awk -F ":" '{print $1}'| grep "${DiskP}"`
if [ $? -eq 0 ];then
   echo
   echo
   echo "--------------------------------------------------------------------------"
   echo "               Formatted Done"
   echo "--------------------------------------------------------------------------"
   echo
   echo
else
   mkfs.xfs -f -n ftype=1 ${DiskP}
fi

if ! grep "${DiskP}" /etc/fstab; then
cat >> /etc/fstab <<EOF
${DiskP} /data                   xfs     defaults        1 0
EOF
echo "--------------------------------------------------------------------------"
fi

# 创建挂载目录
mkdir -p /data
mount ${DiskP}  /data

# 非ROOT用户不允许编辑以下文件
chattr +i /etc/fstab
}

# 判断系统语言
OS_LANG=`echo $LANG | awk -F "." '{print $1}'`
if [ "${OS_LANG}" == "en_US" ];then
   OS_EN
   Mkfs_Disk
elif [ "${OS_LANG}" == "zh_CN" ];then
   OS_CN
   Mkfs_Disk
else
   echo "Sorry script does not support this system."
fi 
