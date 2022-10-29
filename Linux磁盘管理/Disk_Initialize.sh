#!/bin/bash

# 安装软件
EXPECT=`yum list installed | grep -w expect`
if [ $? -eq 0 ];then
   echo "Skip..."
else 
   yum -y install expect
   echo "Done..."
fi

# 解锁文件
chattr -i /etc/fstab

OS_CN() {
Disk=`fdisk -l | grep "磁盘 /dev" | sed -n '2p' | awk '{print $2}' | awk -F '：' '{print $1}' | grep -v "centos-root"`
DiskP=${Disk}1
if [[ "${Disk}" != " " ]];then
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
  echo "The new disk was not found. Exit..."
  exit 1
fi
}

OS_EN() {
Disk=`fdisk -l | grep "Disk /dev" | sed -n '2p' | awk '{print $2}' | awk -F ':' '{print $1}' | grep -v "centos-root"`
DiskP=${Disk}1
if [[ "${Disk}" != " " ]];then
expect -c "
  spawn fdisk $diskf
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
  echo "The new disk was not found. Exit..."
  exit 1
fi
}

Mkfs_Disk() {
sleep 3
# 获取分区UUID
#DiskUUID=`blkid | grep ${DiskP} | awk -F "\"" '{print $2}'`

# 格式化分享
mkfs.xfs -f -n ftype=1 ${DiskP}
if ! grep "${DiskP}" /etc/fstab; then
cat >> /etc/fstab <<EOF
${DiskP} /data                   xfs     defaults        1 0
EOF
echo "${DiskUUID}"
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
