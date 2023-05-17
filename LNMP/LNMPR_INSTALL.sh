#!/usr/bin/env bash
#===============================================================================
#
#          FILE: ChatGPT-Deploy.sh
# 
#         USAGE: ./ChatGPT-Deploy.sh
#
#   DESCRIPTION: ChatGPT商业版项目一键构建、部署脚本
# 
#  ORGANIZATION: DingQz dqzboy.com 浅时光博客
#===============================================================================

SETCOLOR_SKYBLUE="echo -en \\E[1;36m"
SETCOLOR_SUCCESS="echo -en \\E[0;32m"
SETCOLOR_NORMAL="echo  -en \\E[0;39m"
SETCOLOR_RED="echo  -en \\E[0;31m"
SETCOLOR_YELLOW="echo -en \\E[1;33m"

echo
cat << EOF

  $$$$$$\  $$$$$$$\  $$$$$$$$\      $$\      $$\        $$$$$$\  $$\   $$\
 $$  __$$\ $$  __$$\ $$  _____|     $$ |     $$ |      $$  __$$\ $$ | $$  |
 $$ /  $$ |$$ |  $$ |$$ |           $$ |     $$ |      $$ /  $$ |$$ |$$  /
 $$$$$$$$ |$$$$$$$  |$$$$$\         $$ |     $$ |      $$ |  $$ |$$$$$  /
 $$  __$$ |$$  __$$< $$  __|        $$ |     $$ |      $$ |  $$ |$$  $$<
 $$ |  $$ |$$ |  $$ |$$ |           $$ |     $$ |      $$ |  $$ |$$ |\$$\
 $$ |  $$ |$$ |  $$ |$$$$$$$$\       $$$$$$$$$  |       $$$$$$  |$$ | \$$\
 \__|  \__|\__|  \__|\________|      \_________/        \______/ \__|  \__|                                                                                    
                                                                                         
EOF

SUCCESS() {
  ${SETCOLOR_SUCCESS} && echo "------------------------------------< $1 >-------------------------------------"  && ${SETCOLOR_NORMAL}
}

SUCCESS1() {
  ${SETCOLOR_SUCCESS} && echo " $1 "  && ${SETCOLOR_NORMAL}
}

ERROR() {
  ${SETCOLOR_RED} && echo " $1 "  && ${SETCOLOR_NORMAL}
}

INFO() {
  ${SETCOLOR_SKYBLUE} && echo " $1 "  && ${SETCOLOR_NORMAL}
}

WARN() {
  ${SETCOLOR_YELLOW} && echo " $1 "  && ${SETCOLOR_NORMAL}
}

# 进度条
function Progress() {
spin='-\|/'
count=0
endtime=$((SECONDS+3))

while [ $SECONDS -lt $endtime ];
do
    spin_index=$(($count % 4))
    printf "\r[%c] " "${spin:$spin_index:1}"
    sleep 0.1
    count=$((count + 1))
done
}

DONE () {
Progress && SUCCESS1 ">>>>> Done"
echo
}

# OS version
OSVER=$(cat /etc/centos-release | grep -o '[0-9]' | head -n 1)

function CHECKFIRE() {
SUCCESS "Firewall && SELinux detection."
# Check if firewall is enabled
firewall_status=$(systemctl is-active firewalld)
if [[ $firewall_status == 'active' ]]; then
    # If firewall is enabled, disable it
    systemctl stop firewalld
    systemctl disable firewalld &>/dev/null
    INFO "Firewall has been disabled."
else
    INFO "Firewall is already disabled."
fi

# Check if SELinux is enforcing
if sestatus | grep "SELinux status" | grep -q "enabled"; then
    WARN "SELinux is enabled. Disabling SELinux..."
    setenforce 0
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
    INFO "SELinux is already disabled."
else
    INFO "SELinux is already disabled."
fi
DONE
}

function INSTALL_NGINX() {
SUCCESS "Nginx detection and installation."
# 检查是否已安装Nginx
if which nginx &>/dev/null; then
  INFO "Nginx is already installed."
else
  SUCCESS1 "Installing Nginx..."
  NGINX="nginx-1.24.0-1.el${OSVER}.ngx.x86_64.rpm"
  # 下载并安装RPM包
  dnf -y install wget git openssl-devel pcre-devel zlib-devel gd-devel &>/dev/null
  dnf -y install pcre2 &>/dev/null
  rm -f ${NGINX}
  wget http://nginx.org/packages/centos/${OSVER}/x86_64/RPMS/${NGINX} &>/dev/null
  dnf -y install ${NGINX} &>/dev/null
  if [ $? -ne 0 ]; then
    WARN "安装失败，请手动安装，安装成功之后再次执行脚本！"
    echo " 命令：wget http://nginx.org/packages/centos/${OSVER}/x86_64/RPMS/${NGINX} && yum -y install ${NGINX}"
    exit 1
  else
    INFO "Nginx installed."
    rm -f ${NGINX}
  fi
fi


# 检查Nginx是否正在运行
if pgrep "nginx" > /dev/null;then
    INFO "Nginx is already running."
else
    WARN "Nginx is not running. Starting Nginx..."
    systemctl start nginx
    systemctl enable nginx &>/dev/null
    INFO "Nginx started."
fi
DONE
}

function INSTALL_NODEJS() {
SUCCESS "Node.js detection and installation."
# 检查是否安装了Node.js
if ! command -v node &> /dev/null;then
WARN "Node.js 未安装，正在进行安装..."
dnf -y install glibc lsof &>/dev/null
curl -fsSL https://rpm.nodesource.com/setup_lts.x | bash - &>/dev/null
dnf install -y nodejs &>/dev/null
else
    INFO "Node.js 已安装..."
fi

# 检查是否安装了 pm2
if ! command -v pm2 &> /dev/null
then
    WARN "pm2 未安装，正在进行安装..."
    # 安装 pnpm
    npm install -g pm2 &>/dev/null
else
    INFO "pm2 已安装..." 
fi
DONE
}

function INSTALL_REDIS() {
SUCCESS "Redis detection and installation."
# 检查 Redis 是否已经安装
if ! command -v redis-server &> /dev/null
then
    # 如果未安装，则使用 dnf 进行安装
    WARN "Redis is not installed. Installing Redis..."
    sudo dnf install redis -y 2>&1 >/dev/null | grep -E "error|fail|warning"
fi

# 检查 Redis 是否正在运行
redis_status=$(systemctl status redis | grep "Active:")

if [[ $redis_status == *"active (running)"* ]]
then
    # 如果 Redis 已经在运行，则打印提示信息
    INFO "Redis is already running."
else
    # 如果 Redis 没有在运行，则启动 Redis
    WARN "Starting Redis..."
    sudo systemctl restart redis

    # 检查 Redis 是否已经成功启动
    if [[ $(systemctl status redis | grep "Active:") == *"active (running)"* ]]
    then
        SUCCESS1 "Redis has been started."
    else
        ERROR "Failed to start Redis."
    fi
fi
DONE
}

function INSTALL_SQL() {
SUCCESS "MySQL detection and installation."
# 检查 MySQL 是否已经安装
if ! command -v mysql &> /dev/null
then
    # 如果未安装，则使用 dnf 进行安装
    WARN "MySQL is not installed. Installing MySQL..."
    dnf install -y https://repo.mysql.com/mysql80-community-release-el8-5.noarch.rpm 2>&1 >/dev/null | grep -E "error|fail|warning"
    dnf module disable mysql -y &> /dev/null
    dnf config-manager --enable mysql80-community &> /dev/null
    dnf install mysql-community-server mysql-community-devel mysql -y 2>&1 >/dev/null | grep -E "error|fail|warning"
fi

# 检查 MySQL 是否正在运行
mysql_status=$(systemctl status mysqld | grep "Active:")

if [[ $mysql_status == *"active (running)"* ]]
then
    # 如果 MySQL 已经在运行，则打印提示信息
    INFO "MySQL is already running."
else
    # 如果 MySQL 没有在运行，则启动 MySQL
    WARN "Starting MySQL..."
    sudo systemctl restart mysqld

    old_pass=`grep 'temporary password' /var/log/mysqld.log | awk '{print $NF}' | tail -n 1`
    INFO "如果是首次安装的MySQL的ROOT初始密码为：${old_pass}"
    echo ${old_pass} > ${PWD}/mysql_passwd.txt

    # 检查 MySQL 是否已经成功启动
    if [[ $(systemctl status mysqld | grep "Active:") == *"active (running)"* ]]
    then
        SUCCESS1 "MySQL has been started."
    else
        ERROR "Failed to start MySQL."
    fi
fi
DONE
}

function INSTALL_PHP() {
SUCCESS "PHP detection and installation."
# 检查 PHP 是否已经安装
if ! command -v php &> /dev/null
then
    # 如果未安装，则使用 dnf 进行安装
    WARN "PHP is not installed. Installing PHP..."
    dnf -y install https://rpms.remirepo.net/enterprise/remi-release-8.rpm 2>&1 >/dev/null | grep -E "error|fail|warning"
    dnf -y install dnf-utils &>/dev/null
    dnf module enable php:remi-8.2 -y &>/dev/null
    dnf install php-cli php-pear php-mysqlnd php-gd php-common php-fpm php-intl php-xml php-opcache php-pecl-apcu php-pdo php-gmp php-process php-pecl-imagick php-devel php-mbstring php-zip php-ldap php-imap php-pecl-mcrypt php-pecl-redis php-fileinfo -y 2>&1 >/dev/null | grep -E "error|fail|warning"
fi

# 检查 PHP 是否正在运行
php_status=$(systemctl status php-fpm | grep "Active:")

if [[ $php_status == *"active (running)"* ]]
then
    # 如果 PHP 已经在运行，则打印提示信息
    INFO "PHP is already running."
else
    # 如果 PHP 没有在运行，则启动 PHP
    WARN "Starting PHP..."
    sudo systemctl start php-fpm

    # 检查 PHP 是否已经成功启动
    if [[ $(systemctl status php-fpm | grep "Active:") == *"active (running)"* ]]
    then
        SUCCESS1 "PHP has been started."
    else
        ERROR "Failed to start PHP."
    fi
fi
DONE
}

function prompt() {
SUCCESS "Basic environment deployment completed."
echo """
基础环境已经部署完成,接下来的项目部署请参考下面文章教程进行搭建：
【浅时光博客】https://www.dqzboy.com/14100.html
"""
SUCCESS "------------------END------------------"
}

function main() {
    CHECKFIRE
    INSTALL_NGINX
    INSTALL_NODEJS
    INSTALL_REDIS
    INSTALL_SQL
    INSTALL_PHP
    prompt
}
main
