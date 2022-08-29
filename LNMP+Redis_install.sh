#!/bin/bash
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[36m'
#清除颜色
plain='\033[0m'
white='\033[37m'
#分红
pink='\E[1;35m'
#紫色
purple='\033[35m'
#黄色警示闪烁
SHAN='\E[33;5m'
# 清除颜色
RES='\E[0m'
echo 
echo
echo -e "${SHAN} 注意事项：
（1）此脚本运行需要确保服务器可以连接至外网,并且在网络正常的环境下运行！
（2）此脚本会卸载原有的数据库,运行此脚本前请确保已经备份了原有数据库数据(如无则忽略此提示)！${RES}"
echo "-----------------------------------------------------------------------------------------------------------------------------------"
echo -e "${purple}
------------------------
| 软件名称  | 安装版本 | 
------------------------
| Nginx     | 最新版本 |
------------------------
| MySQL     | 5.7/8.0  |
------------------------
| PHP       | 74 / 80  |
------------------------
| Redis     |  5/6/7   |
------------------------
${RES}"

read -p "是否确认继续?[yes/no]" come
if [ ${come} == "no" ];then
   echo -e "${red} 正在退出程序.....${RES}"
   sleep 3
   exit 1
elif  [ ${come} == "yes" ];then
   echo -e "${blue}继续部署程序.....${RES}"
else
   echo -e "${red} 输入参数有误,退出程序.....${RES}"
   exit 2
fi

echo
System_initial() {
echo -e "${blue}
#++++++++++++++++++++++++++++++++++++++++++++++++++++#
#                                                    #
#            开始对服务器系统进行初始化              #
#                                                    # 
#++++++++++++++++++++++++++++++++++++++++++++++++++++#
${plain}"

cat > /etc/motd <<EOF

	Welcome your arrival

EOF


echo -e "${yellow}
+------------------------------+
|        0.系统内核升级        |
+------------------------------+
${plain}"
rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org &>/dev/null
rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-5.el7.elrepo.noarch.rpm &>/dev/null

yum install --enablerepo=elrepo-kernel --skip-broken -y kernel-ml kernel-ml-headers kernel-ml-devel kernel-ml-tools kernel-ml-tools-libs kernel-ml-tools-libs-devel &>/dev/null

echo -e "${pink}------------------------------------------------------
Please select the installed version number:
`awk -F\' '$1=="menuentry " {print i++ " : " $2}' /etc/grub2.cfg`
------------------------------------------------------${plain}"
read -p "Please enter the installed serial number: " input
grub2-set-default ${input}

echo -e "${yellow}
+------------------------------+
|        1. 时 区 检 查        |
+------------------------------+
${plain}"

date=$(date +%F-%T)
echo "当前时间：${date}"
echo "当前时区：$(timedatectl |grep "Time zone"|awk -F ":" '{print $2}')"
if [ $(date +%Z) == "CST" ];then
    echo " "
else
    echo "当前系统时区非CST,将进行修改时区"
    timedatectl set-timezone Asia/Shanghai
fi

echo -e "${yellow}
+------------------------------+
|        2. DNS解析配置        |
+------------------------------+
${plain}"

echo -e "${green} 添加阿里云公共DNS解析服务器${plain}"
if ! grep "nameserver 223.5.5.5" /etc/resolv.conf &>/dev/null;then
cat >> /etc/resolv.conf << EOF
nameserver 223.5.5.5
nameserver 223.5.5.6
EOF
fi

echo -e "${yellow}
+------------------------------+
|        3. 下载依赖包         |
+------------------------------+
${plain}"

echo -e "${green}正在下载常用命令和工具，请稍等...${white}"
echo -e "${SHAN}请确保服务器可连接外网,并且需要保证网络正常${RES}"


## 安装阿里CentOS-Base源
mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.bak &>/dev/null
curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-7.repo &>/dev/null 
curl -o /etc/yum.repos.d/epel-7.repo http://mirrors.aliyun.com/repo/epel-7.repo &>/dev/null

## Nginx安装YUM源
cat > /etc/yum.repos.d/nginx.repo << \EOF
[nginx-stable]
name=nginx stable repo
baseurl=http://nginx.org/packages/centos/$releasever/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true

[nginx-mainline]
name=nginx mainline repo
baseurl=http://nginx.org/packages/mainline/centos/$releasever/$basearch/
gpgcheck=1
enabled=0
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true
EOF

## PHP安装YUM源
rpm -ivh https://mirrors.aliyun.com/remi/enterprise/remi-release-7.rpm --force --nodeps &>/dev/null
sed -i  's/https*:\/\/rpms.remirepo.net/https:\/\/mirrors.aliyun.com\/remi/g'  /etc/yum.repos.d/remi*
sed -i 's/#baseurl/baseurl/g' /etc/yum.repos.d/remi*
sed -i 's|^mirrorlist|#mirrorlist|' /etc/yum.repos.d/remi*

## Redis安装YUM源
yum install -y http://rpms.famillecollet.com/enterprise/remi-release-7.rpm --force --nodeps &>/dev/null

## 清除YUM缓存并重新生成YUM缓存
yum clean all &>/dev/null
yum makecache &>/dev/null


yum -y install gcc gcc-c++ libaio make cmake zlib-devel openssl-devel pcre pcre-devel wget git curl lynx lftp mailx mutt rsync ntp net-tools vim lrzsz screen sysstat yum-plugin-security yum-utils createrepo bash-completion zip unzip bzip2 tree tmpwatch pinfo man-pages lshw pciutils gdisk system-storage-manager git  gdbm-devel sqlite-devel bind-utils telnet lsof &>/dev/null
source /usr/share/bash-completion/bash_completion

echo -e "${yellow}
+------------------------------+
|        4. 时 间 同 步        |
+------------------------------+
${plain}"

systemctl start ntpd 2>/dev/null
systemctl enable ntpd 2>/dev/null 
status=`systemctl status ntpd | grep "Active"  | awk -F " " {'print $3'}`
echo -e "当前ntpd服务状态为：${green}${status}${plain}"

echo -e "${green}正在同步互联网时间，请稍等...${white}"
echo -e "${SHAN}请确保服务器可连接外网,并且需要保证网络正常${RES}"
ntpdate -d cn.pool.ntp.org &>/dev/null
ntpdate cn.pool.ntp.org


echo -e "${yellow}
+------------------------------+
|        5. 创 建 目 录        |
+------------------------------+
${plain}"

echo -e "${green}下载的所有程序源码包存储在/opt/soft目录下${plain}"
package="/opt/soft"
mkdir -p $package 1>/dev/null
mkdir -p /data
echo -e "${yellow}


+------------------------------+
|        6. 关闭SELINUX        |
+------------------------------+
${plain}"

echo -e "${green}正在关闭SELINUX，请稍等...${white}"
setenforce 0 >/dev/null 2>&1
sed -i 's/^SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux >/dev/null 2>&1
sed -i 's/^SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config >/dev/null 2>&1
setenforce 0
getenforce

#关闭NOZEROCONF
sed -i '/NOZEROCONF.*/d' /etc/sysconfig/network
echo "NOZEROCONF=yes" >> /etc/sysconfig/network

echo -e "${yellow}
+------------------------------+
|     7.关闭NetworkManager     |
+------------------------------+
${plain}"
systemctl stop NetworkManager &>/dev/null
systemctl disable NetworkManager &>/dev/null

echo -e "${yellow}
+------------------------------+
|        8. 减少SWAP使用       |
+------------------------------+
${plain}"

echo -e "${green}正在调整系统SWAP参数，请稍等...${white}"
echo "0" > /proc/sys/vm/swappiness

echo -e "${yellow}
+------------------------------+
|        9. 系统内核优化       |
+------------------------------+
${plain}"

echo -e "${green}正在调整系统内核参数，请稍等...${white}"
if ! grep "net.ipv4.ip_forward=1" /etc/sysctl.d/system.conf &>/dev/null;then
cat > /etc/sysctl.d/system.conf <<EOF
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
net.ipv4.neigh.default.gc_thresh1=1024
net.ipv4.neigh.default.gc_thresh2=2048
net.ipv4.neigh.default.gc_thresh3=4096
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
EOF

#不重启更新内核参数
sysctl -p &>/dev/null
sysctl --system &>/dev/null
fi

echo -e "${yellow}
+------------------------------+
|      10.开启历史命令记录     |
+------------------------------+
${plain}"

echo -e "${green}正在修改配置文件，请稍等...${white}"

if ! grep 'HISTTIMEFORMAT' /etc/profile &>/dev/null;then
    echo 'export HISTTIMEFORMAT="[执行时间:%F %T] [执行用户:`whoami`] "' >> /etc/profile
fi
source /etc/profile


echo -e "${yellow}
+------------------------------+
|        11.禁止发送邮件       |
+------------------------------+
${plain}"

echo -e "${green}禁止定时任务发送邮件，请稍等...${white}"
#关闭发邮件
if [ -z "$(grep MAILCHECK /etc/profile)" ];then
    echo 'unset MAILCHECK'>>/etc/profile
fi
sed -i "s/^MAILTO=root/MAILTO=\"\"/g" /etc/crontab


echo -e "${yellow}
+------------------------------+
|     12.调整最大文件打开数    |
+------------------------------+
${plain}"

echo -e "${green}正在调整最大文件打开数，请稍等...${white}"
if ! grep "* soft nofile 65535" /etc/security/limits.conf;then
cat >> /etc/security/limits.conf <<EOF
* soft nofile 65536
* hard nofile 65536
* soft nproc 65536
* hard nproc 65536
EOF
fi
}

Nginx() {
echo -e "${blue}
#++++++++++++++++++++++++++++++++++++++++++++++++++++#
#                                                    #
#           开始对服务器系统安装Nginx服务            #
#                                                    # 
#++++++++++++++++++++++++++++++++++++++++++++++++++++#
${plain}"

echo -e "${yellow}
+------------------------------+
|        1. 安 装 程 序        |
+------------------------------+
${plain}"
echo -e "${green}正在安装程序，请稍等...${white}"
yum-config-manager --enable nginx-mainline &>/dev/null

#安装Nginx
yum install nginx -y &>/dev/null

echo -e "${yellow}
+------------------------------+
|        2. 修 改 配 置        |
+------------------------------+
${plain}"

echo -e "${green}正在修改配置文件，请稍等...${white}"

CPU=`lscpu |grep "^CPU(s)" |awk '{print $2}'`
sed -i "s/worker_processes  1;/worker_processes  "${CPU}";/g" /etc/nginx/nginx.conf

echo -e "${yellow}
+------------------------------+
|        3. 启 动 程 序        |
+------------------------------+
${plain}"

echo -e "${green}正在启动程序，请稍等...${white}"
systemctl start nginx &>/dev/null 

echo -e "${yellow}
+------------------------------+
|        4. 检 查 程 序        |
+------------------------------+
${plain}"

status=`lsof -i:80|awk '{print $1}'|grep -w nginx|wc -l`
if [ $status != 0 ];then
   echo "Nginx服务器已经正常启动"
   echo "放行服务监听端口"
      firewall-cmd --zone=public --add-port=80/tcp --permanent 2>/dev/null
      firewall-cmd --reload
else
   echo "Nginx服务未能正常启动，请查看日志"
fi

echo -e "${yellow}
+------------------------------+
|        5.加入开机自启        |
+------------------------------+
${plain}"
systemctl enable nginx &>/dev/null 
echo -e "${green}已经将Nginx程序加入开机自启服务中...${white}"

}

## 检查数据是否存在数据库
Uninstall_Mari() {
echo -e "${green}正在检查系统是否已经安装数据库，请稍等...${white}"

rpm -qa | grep mariadb || rpm -qa|grep mysql-community &>/dev/null
if [ $? -eq 0 ];then
    echo "系统存在数据库"
    echo "正在执行卸载..."
    rpm -qa | grep mariadb | xargs rpm -e --nodeps &>/dev/null
    rpm -qa|grep mysql-community | xargs rpm -e --nodeps &>/dev/null
else
   echo -e "${blue}系统未安装数据库，正在执行MySQL数据库安装...${RES}"
fi

echo -e "${green}正在下载程序，请稍等...${white}"
echo -e "${SHAN}请确保服务器可连接外网,并且需要保证网络正常${RES}"
}

## 部署MySQL服务
MySQL() {
echo -e "${blue}
#++++++++++++++++++++++++++++++++++++++++++++++++++++#
#                                                    #
#           开始对服务器系统安装MySQL服务            #
#                                                    # 
#++++++++++++++++++++++++++++++++++++++++++++++++++++#
${plain}"

echo -e "${yellow}
+------------------------------+
|        1. 下载程序包         |
+------------------------------+
${plain}"

echo -e "${pink}------------------------------------------------------
Please select the installed version number:(1-3)
(1) MySQL-5.7
(2) MySQL-8.0
(3) Exit Menu.
------------------------------------------------------${plain}"
read -p "Please enter the installed serial number: " input

echo -e "${purple}------------------------------------------------------${white}"
case $input in 
	1) echo "Download...mysql-5.7-community"
	   Uninstall_Mari
	   cd $package && mkdir -p mysql57 && cd mysql57
           wget https://mirrors.huaweicloud.com/mysql/Downloads/MySQL-5.7/mysql-community-common-5.7.35-1.el7.x86_64.rpm  &>/dev/null
           wget https://mirrors.huaweicloud.com/mysql/Downloads/MySQL-5.7/mysql-community-libs-5.7.35-1.el7.x86_64.rpm  &>/dev/null
           wget https://mirrors.huaweicloud.com/mysql/Downloads/MySQL-5.7/mysql-community-libs-compat-5.7.35-1.el7.x86_64.rpm  &>/dev/null
           wget https://mirrors.huaweicloud.com/mysql/Downloads/MySQL-5.7/mysql-community-devel-5.7.35-1.el7.x86_64.rpm  &>/dev/null
           wget https://mirrors.huaweicloud.com/mysql/Downloads/MySQL-5.7/mysql-community-client-5.7.35-1.el7.x86_64.rpm  &>/dev/null
           wget https://mirrors.huaweicloud.com/mysql/Downloads/MySQL-5.7/mysql-community-server-5.7.35-1.el7.x86_64.rpm  &>/dev/null

   	   ;;
	2) echo "Download...mysql-8.0-community"
           Uninstall_Mari
	   cd $package && mkdir -p mysql80 && cd mysql80
           wget https://mirrors.huaweicloud.com/mysql/Downloads/MySQL-8.0/mysql-community-common-8.0.27-1.el7.x86_64.rpm  &>/dev/null
           wget https://mirrors.huaweicloud.com/mysql/Downloads/MySQL-8.0/mysql-community-libs-8.0.27-1.el7.x86_64.rpm  &>/dev/null
           wget https://mirrors.huaweicloud.com/mysql/Downloads/MySQL-8.0/mysql-community-libs-compat-8.0.27-1.el7.x86_64.rpm  &>/dev/null
           wget https://mirrors.huaweicloud.com/mysql/Downloads/MySQL-8.0/mysql-community-devel-8.0.27-1.el7.x86_64.rpm  &>/dev/null
           wget https://mirrors.huaweicloud.com/mysql/Downloads/MySQL-8.0/mysql-community-client-plugins-8.0.27-1.el7.x86_64.rpm &>/dev/null
           wget https://mirrors.huaweicloud.com/mysql/Downloads/MySQL-8.0/mysql-community-client-8.0.27-1.el7.x86_64.rpm  &>/dev/null
           wget https://mirrors.huaweicloud.com/mysql/Downloads/MySQL-8.0/mysql-community-server-8.0.27-1.el7.x86_64.rpm  &>/dev/null
	   ;;
	3) echo "Exit Download"
	   exit 1
           ;;
esac


echo -e "${yellow}
+------------------------------+
|        2. 安 装 程 序        |
+------------------------------+
${plain}"

echo -e "${green}正在安装程序，请稍等...${white}"
case $input in
        1) echo "Installing...mysql-5.7-community"
           cd $package/mysql57
           yum -y install mysql-community-* &>/dev/null
           ;;
        2) echo "Installing...mysql-8.0-community"
           cd $package/mysql80
           yum -y install mysql-community-* &>/dev/null
           ;;
        3) echo "${SHAN}Exit installation${white}"
           exit 1
           ;;
esac

echo -e "${yellow}
+------------------------------+
|        3. 修 改 配 置        |
+------------------------------+
${plain}"

echo -e "${green}正在修改配置文件，请稍等...${white}"

cat > /etc/my.cnf << EOF
[mysqld]
datadir=/data/mysql
socket=/var/lib/mysql/mysql.sock

symbolic-links=0
log-error=/var/log/mysqld.log
pid-file=/var/run/mysqld/mysqld.pid
character-set-server=utf8mb4
default-storage-engine=INNODB
log_output=file
slow_query_log=on
slow_query_log_file =/var/lib/mysql/slowlog
log_queries_not_using_indexes=on
long_query_time=1
explicit_defaults_for_timestamp=1
EOF

echo -e "${yellow}
+------------------------------+
|        4. 启 动 程 序        |
+------------------------------+
${plain}"

echo -e "${green}正在启动程序，请稍等...${white}"
systemctl start mysqld 2>/dev/null
systemctl enable mysqld 2>/dev/null

echo -e "${yellow}
+------------------------------+
|        5. 检 查 服 务        |
+------------------------------+
${plain}"

echo -e "${green}正在检查程序状态，请稍等...${white}"

status=`lsof -i:3306|awk '{print $1}'|grep -w mysqld|wc -l`
if [ $status != 0 ];then
   echo "MySQL服务器已经正常启动"
   echo "放行服务监听端口"
      firewall-cmd --zone=public --add-port=3306/tcp --permanent 2>/dev/null
      firewall-cmd --reload
else
   echo "MySQL服务未能正常启动，请查看日志"
fi

}

MySQL_PASSWD() {
echo -e "${yellow}
+------------------------------+
|       获取MySQL初始密码      |
+------------------------------+
${plain}"

echo -e "${green}正在获取MySQL数据库root初始登入认证密码，请稍等...${white}"
if grep "temporary password" /var/log/mysqld.log >/dev/null ;then
    echo -e "${green}数据库登入root初始密码如下：${white}"
    grep 'temporary password' /var/log/mysqld.log|awk '{print $NF}'
    echo -e "${green}数据库登入root初始密码已保存在 /root/mysql_passwd.txt中 ${white}"
    grep 'temporary password' /var/log/mysqld.log|awk '{print $NF}'|xargs echo > /root/mysql_passwd.txt
    echo "==============================================================================================="
else
    echo -e "${red}数据库root初始密码未生成，请检查日志${white}"
fi
}

PHP() {
echo -e "${blue}
#++++++++++++++++++++++++++++++++++++++++++++++++++++#
#                                                    #
#           开始对服务器系统安装 PHP 服务            #
#                                                    # 
#++++++++++++++++++++++++++++++++++++++++++++++++++++#
${plain}"

echo -e "${yellow}
+------------------------------+
|        1. 安装程序包         |
+------------------------------+
${plain}"

echo -e "${pink}------------------------------------------------------
Please select the installed version number:(1-3)
(1) PHP74
(2) PHP80
(3) Exit Menu.
------------------------------------------------------${plain}"
read -p "Please enter the installed serial number: " input
echo -e "${purple}------------------------------------------------------${white}"
echo -e "${green}正在安装程序，请稍等...${white}"
case $input in
        1) echo "Installing...PHP74"
           yum-config-manager --enable remi-php74 &>/dev/null
           yum -y install php-cli php-pear bcmath php-pecl-jsond-devel php-mysqlnd php-gd php-common php-fpm php-intl php-cli php-xml php-opcache php-pecl-apcu php-pdo php-gmp php-process php-pecl-imagick php-devel php-mbstring php-zip php-ldap php-imap php-pecl-mcrypt --skip-broken &>/dev/null
           ;;
        2) echo "Installing...PHP80"
           yum-config-manager --enable remi-php80 &>/dev/null
           yum -y install php-cli php-pear bcmath php-pecl-jsond-devel php-mysqlnd php-gd php-common php-fpm php-intl php-cli php-xml php-opcache php-pecl-apcu php-pdo php-gmp php-process php-pecl-imagick php-devel php-mbstring php-zip php-ldap php-imap php-pecl-mcrypt --skip-broken &>/dev/null
           ;;
        3) echo "${SHAN}Exit installation${white}"
           exit 1
           ;;
esac
## 打印出PHP版本
php -version


echo -e "${yellow}
+------------------------------+
|        2. 修 改 配 置        |
+------------------------------+
${plain}"

echo -e "${green}正在修改配置文件，请稍等...${white}"
sed -i 's/group = apache/group = nginx/g' /etc/php-fpm.d/www.conf
sed -i 's/user = apache/user = nginx/g' /etc/php-fpm.d/www.conf

echo -e "${yellow}
+------------------------------+
|        3. 启 动 程 序        |
+------------------------------+
${plain}"

echo -e "${green}正在启动程序，请稍等...${white}"
systemctl start php-fpm.service 2>/dev/null 
systemctl enable php-fpm.service 2>/dev/null 


echo -e "${yellow}
+------------------------------+
|        4. 检 查 服 务        |
+------------------------------+
${plain}"

echo -e "${green}正在检查程序状态，请稍等...${white}"

status=`lsof -i:9000|awk '{print $1}'|grep -w php-fpm|wc -l`
if [ $status != 0 ];then
   echo "PHP服务器已经正常启动"
   echo "放行服务监听端口"
      firewall-cmd --zone=public --add-port=9000/tcp --permanent 2>/dev/null 
      firewall-cmd --reload
else
   echo "PHP服务未能正常启动，请查看日志"
fi

}

## 定义下载文件打印函数
Download() {
    echo -e "${red}请确保服务器可连接外网${white}"
    echo -e "${purple}------------------------------------------------------${white}"
    echo -e "${green}正在下载程序，请稍等...${white}"
}

## Redis
#Redis_make() {
#    make &>/dev/null
#    make install PREFIX=/usr/local/redis &>/dev/null
#    cd ./bin && cp * /usr/local/bin/
#}

Redis() {
echo -e "${blue}
#++++++++++++++++++++++++++++++++++++++++++++++++++++#
#                                                    #
#           开始对服务器系统安装Redis服务            #
#                                                    # 
#++++++++++++++++++++++++++++++++++++++++++++++++++++#
${plain}"

echo -e "${yellow}
+------------------------------+
|        1. 安装程序包         |
+------------------------------+
${plain}"
echo -e "${pink}------------------------------------------------------
Please select the installed version number:(1-4)
(1) Redis-5.0
(2) Redis-6.0
(3) Redis-7.0
(4) Exit Menu.
------------------------------------------------------${plain}"
read -p "Please enter the installed serial number: " input
echo -e "${purple}------------------------------------------------------${white}"
echo -e "${green}正在安装程序，请稍等...${white}"
case $input in 
	1) echo "Download...Redis-5.0"
           yum --enablerepo=remi install redis-5.0.14 -y &>/dev/null
	;;
	2) echo "Download...Redis-6.0"
           yum --enablerepo=remi install redis-6.2.7 -y &>/dev/null
	;;
        3)
           echo "Download...Redis-7.0"
           yum --enablerepo=remi install redis-7.0.2 -y &>/dev/null
        ;;
	4) echo "Exit Download"
	   exit 1
        ;;
esac

echo -e "${yellow}
+------------------------------+
|        2. 启动服务程序       |
+------------------------------+
${plain}"

echo -e "${green}正在启动程序，请稍等...${white}"
if ! grep "echo 511 > /proc/sys/net/core/somaxconn" &>/dev/null /etc/rc.d/rc.local;then
    echo "echo 511 > /proc/sys/net/core/somaxconn" >> /etc/rc.d/rc.local
fi
systemctl daemon-reload &>/dev/null
systemctl enable redis &>/dev/null
systemctl start redis &>/dev/null

echo -e "${yellow}
+------------------------------+
|        3. 检查服务状态       |
+------------------------------+
${plain}"

status=`lsof -i:6379|awk '{print $1}'|grep -w redis-ser | wc -l`
if [ $status != 0 ];then
   echo -e "${green}Redis服务器已经正常启动${white}"
   echo -e "${green}放行服务监听端口${white}"
      firewall-cmd --zone=public --add-port=6379/tcp --permanent &>/dev/null
      firewall-cmd --reload
else
   echo "${red}Redis服务未能正常启动，请查看日志${RES}"
fi
}

REBOOT(){
    echo "------------------------------------------------------------------------------------------"
    echo -e "${red} 注: 如果您选择了新的系统内核,请手动执行 reboot 重启服务器生效！！！${RES}"
}

main() {
    System_initial
    Nginx
    MySQL
    PHP
    Redis
    MySQL_PASSWD
    REBOOT
}
main
