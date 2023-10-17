#!/usr/bin/env bash
#===============================================================================
#
#          FILE: setup_server.sh
#
#         USAGE: ./setup_server.sh
#
#       ORGANIZATION: Ding Qin Zheng
#===============================================================================

SETCOLOR_SKYBLUE="echo -en \\E[1;36m"
SETCOLOR_SUCCESS="echo -en \\E[0;32m"
SETCOLOR_NORMAL="echo  -en \\E[0;39m"
SETCOLOR_RED="echo  -en \\E[0;31m"
SETCOLOR_YELLOW="echo -en \\E[1;33m"
GREEN="\033[1;32m"
RESET="\033[0m"
PURPLE="\033[35m"

SUCCESS() {
  ${SETCOLOR_SUCCESS} && echo "------------------------------------< $1 >-------------------------------------"  && ${SETCOLOR_NORMAL}
}

SUCCESS1() {
  ${SETCOLOR_SUCCESS} && echo "$1"  && ${SETCOLOR_NORMAL}
}

ERROR() {
  ${SETCOLOR_RED} && echo "$1"  && ${SETCOLOR_NORMAL}
}

INFO() {
  ${SETCOLOR_SKYBLUE} && echo "------------------------------------ $1 -------------------------------------"  && ${SETCOLOR_NORMAL}
}

INFO1() {
  ${SETCOLOR_SKYBLUE} && echo "$1"  && ${SETCOLOR_NORMAL}
}

WARN() {
  ${SETCOLOR_YELLOW} && echo "$1"  && ${SETCOLOR_NORMAL}
}

# 检查命令执行结果，并采取相应的操作
check_command() {
    if [ $? -eq 0 ]; then
        SUCCESS1 "$1 执行成功"
    else
        ERROR "$1 执行失败"
        exit 1  # 或者采取其他错误处理操作
    fi
}

function os_info() {
INFO "系统欢迎信息"
cat > /etc/motd <<EOF

    Welcome to YUN Cloud Server

EOF
check_command "设置系统欢迎信息"
}

function host_name() {
INFO "配置系统主机名"
read -e -p "$(echo -e ${GREEN}"请输入修改的主机名称: "${RESET})" hostname
hostnamectl --static set-hostname $hostname
# 在设置主机名后，可以添加以下检查
if [ "$(hostnamectl --static)" == "$hostname" ]; then
    SUCCESS1 "主机名已设置为 $hostname"
else
    ERROR "设置主机名失败"
    exit 1
fi
}

function firewalld_disable() {
INFO "关闭系统防火墙"
systemctl stop firewalld && systemctl disable firewalld
if ! systemctl is-active --quiet firewalld; then
    SUCCESS1 "防火墙已成功关闭"
else
    ERROR "关闭防火墙失败"
    exit 1
fi

sed -ri 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config 
setenforce 0 
if [ "$(getenforce)" == "Disabled" ]; then
    SUCCESS1 "SELinux 已禁用"
else
    ERROR "禁用 SELinux 失败"
fi

INFO "调整NetworkManager"
SUCCESS1 "调整NetworkManager配置，防止重启网卡自动恢复默认的DNS配置"
if ! grep "dns=none" /etc/NetworkManager/NetworkManager.conf &>/dev/null; then
    sed -i '/plugins=keyfile/a\dns=none' /etc/NetworkManager/NetworkManager.conf
    SUCCESS1 "NetworkManager配置已更新"

    systemctl restart NetworkManager
    systemctl enable NetworkManager
    if ! systemctl is-active --quiet NetworkManager; then
        SUCCESS1 "NetworkManager已成功重启"
    else
        ERROR "重启NetworkManager失败"
        exit 1
    fi
else
    SUCCESS1 "NetworkManager配置已经是最新的"
fi
check_command "调整NetworkManager"
}

function systemd_pager() {
INFO "规避系统分页显示"
if ! grep "SYSTEMD_PAGER" /etc/profile &>/dev/null;then
cat >> /etc/profile <<\EOF
export SYSTEMD_PAGER=""
EOF
    source /etc/profile
    SUCCESS1 "已成功设置 SYSTEMD_PAGER"
else
    SUCCESS1 "SYSTEMD_PAGER配置已经是最新的"
fi

check_command "分页显示规避"
}

function os_tools() {
INFO "安装工具包和开发工具"
WARN "安装工具包和开发工具中,请耐心等待安装完成！"
dnf -y update &>/dev/null

dnf install -y epel-release &>/dev/null 
dnf -y groupinstall "Development Tools" &>/dev/null

dnf -y install wget git curl lynx lftp  mutt rsync  net-tools vim lrzsz screen sysstat dnf-utils createrepo bash-completion zip unzip bzip2 tmpwatch lshw pciutils gdisk sqlite-devel bind-utils telnet lsof nethogs iotop iftop htop tcpdump nc dos2unix nmap tree tar &>/dev/null

dnf -y install gcc gcc-c++ libaio make cmake zlib-devel openssl openssl-devel pcre pcre-devel ncurses-devel unixODBC readline-devel &>/dev/null

source /usr/share/bash-completion/bash_completion
check_command "工具包和开发工具安装"
}

function swap_disable() {
INFO "关闭系统swap交换分区"
swapoff -a && free -h|grep Swap
check_command "Swap交换分区关闭"
}

function os_setup() {
INFO "开启系统历史命令记录"
if ! grep 'HISTTIMEFORMAT' /etc/profile &>/dev/null;then
    echo 'export HISTTIMEFORMAT="[执行时间:%F %T] [执行用户:`whoami`] "' >> /etc/profile
fi
source /etc/profile

if ! grep 'HISTTIMEFORMAT' ~/.bashrc &>/dev/null;then
    echo 'export HISTTIMEFORMAT="[执行时间:%F %T] [执行用户:`whoami`] "' >> ~/.bashrc
fi
source ~/.bashrc

check_command "系统历史命令记录修改"

INFO "禁止定时任务发送邮件"
if ! grep 'unset MAILCHECK' /etc/profile;then
    echo 'unset MAILCHECK'>>/etc/profile
fi
sed -i "s/^MAILTO=root/MAILTO=\"\"/g" /etc/crontab
check_command "禁止定时任务发送邮件"

INFO "关闭DNS PTR反向查询"
sed -ri 's/#UseDNS yes/UseDNS no/g' /etc/ssh/sshd_config
systemctl restart sshd
check_command "DNS PTR反向查询关闭"
}

function os_kernel() {
INFO "调整系统内核优化参数"
cat > /etc/sysctl.d/system.conf <<EOF
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
net.ipv4.neigh.default.gc_thresh1=1024
net.ipv4.neigh.default.gc_thresh2=2048
net.ipv4.neigh.default
gc_thresh3=4096
vm.swappiness=0
vm.overcommit_memory=1
vm.panic_on_oom=0
vm.max_map_count=262144
fs.inotify.max_user_instances=8192
fs.inotify.max_user_watches=1048576
fs.file-max=52706963
fs.nr_open=52706963
net.ipv6.conf.all.disable_ipv6=1
net.netfilter.nf_conntrack_max=2310720
net.ipv4.tcp_max_syn_backlog=8096
net.core.netdev_max_backlog=10000
net.core.somaxconn=32768
kernel.pid_max=4194304
net.core.default_qdisc=cake
net.ipv4.tcp_congestion_control=bbr
EOF

# 在不重启的情况下应用更改，请执行
sysctl -p /etc/sysctl.d/system.conf &>/dev/null
sysctl --system &>/dev/null

check_command "系统内核参数调整"


INFO "调整系统文件描述符"
if ! grep "* soft nofile 65535" /etc/security/limits.conf &>/dev/null;then
cat >> /etc/security/limits.conf <<EOF
* soft nofile 65535
* hard nofile 65535
* soft nproc 65535
* hard nproc 65535
EOF
fi
check_command "系统文件描述符调整"
}

function os_date() {
INFO "检查服务器系统时区"
date=$(date +%F-%T)
echo "当前时间：${date}"
echo "当前时区：$(timedatectl |grep "Time zone"|awk -F ":" '{print $2}')"
if [ $(date +%Z) == "CST" ];then
    echo "当前系统时区为CST"
else
    echo "当前系统时区非CST，将进行修改时区"
    timedatectl set-timezone Asia/Shanghai
fi
check_command "系统时区调整"
}

function irqbalance_disable() {
INFO "关闭系统irqbalance"
systemctl stop irqbalance.service && systemctl disable irqbalance.service
if ! systemctl is-active --quiet irqbalance; then
    SUCCESS1 "irqbalance已成功关闭"
else
    ERROR "关闭NetworkManager失败"
    exit 1
fi
check_command "关闭系统irqbalance"
}

function os_rm() {
INFO "调整rm命令操作姿势"
if ! grep -q "rm_prompt" /etc/profile;then
cat >> /etc/profile <<\EOF
alias rm='rm_prompt'
rm_prompt() {
    read -e -p "Are you sure you want to remove? [y/n] " choice
    if [ "$choice" == "y" ]; then
        /bin/rm "$@"
    fi
}
EOF
fi

source /etc/profile

if ! grep -q "rm_prompt" ~/.bashrc;then
cat >> ~/.bashrc <<\EOF
alias rm='rm_prompt'
rm_prompt() {
    read -e -p "Are you sure you want to remove? [y/n] " choice
    if [ "$choice" == "y" ]; then
        /bin/rm "$@"
    fi
}
EOF
fi

source ~/.bashrc
check_command "调整rm命令操作"
}

function os_reboot() {
INFO "操作系统初始化完成"
WARN "系统初始化完成，请手动执行 reboot 重启服务器！"
}

main() {
  os_info
  host_name
  firewalld_disable
  systemd_pager
  os_tools
  swap_disable
  os_setup
  os_kernel
  os_date
  irqbalance_disable
  os_rm
  os_reboot
}
main
