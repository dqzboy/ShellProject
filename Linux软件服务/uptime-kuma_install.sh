#!/usr/bin/env bash
#===============================================================================
#
#          FILE: uptime-kuma_install.sh
#
#         USAGE: ./uptime-kuma_install.sh
#
#   DESCRIPTION: 一键部署 uptime-kuma 监控平台工具
#
#  ORGANIZATION: DingQz dqzboy.com
#===============================================================================

echo
cat << EOF

    ██╗   ██╗██████╗ ████████╗██╗███╗   ███╗███████╗    ██╗  ██╗██╗   ██╗███╗   ███╗ █████╗ 
    ██║   ██║██╔══██╗╚══██╔══╝██║████╗ ████║██╔════╝    ██║ ██╔╝██║   ██║████╗ ████║██╔══██╗
    ██║   ██║██████╔╝   ██║   ██║██╔████╔██║█████╗      █████╔╝ ██║   ██║██╔████╔██║███████║
    ██║   ██║██╔═══╝    ██║   ██║██║╚██╔╝██║██╔══╝      ██╔═██╗ ██║   ██║██║╚██╔╝██║██╔══██║
    ╚██████╔╝██║        ██║   ██║██║ ╚═╝ ██║███████╗    ██║  ██╗╚██████╔╝██║ ╚═╝ ██║██║  ██║
     ╚═════╝ ╚═╝        ╚═╝   ╚═╝╚═╝     ╚═╝╚══════╝    ╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚═╝╚═╝  ╚═╝

EOF


GREEN="\033[0;32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"
BLUE="\033[0;34m"
MAGENTA="\033[0;35m"
CYAN="\033[0;36m"
WHITE="\033[1;37m"
BLACK="\033[0;30m"
LIGHT_GREEN="\033[1;32m"
LIGHT_RED="\033[1;31m"
LIGHT_YELLOW="\033[1;33m"
LIGHT_BLUE="\033[1;34m"
LIGHT_MAGENTA="\033[1;35m"
LIGHT_CYAN="\033[1;36m"
BOLD="\033[1m"
UNDERLINE="\033[4m"
BLINK="\033[5m"
REVERSE="\033[7m"

INFO="[${GREEN}INFO${RESET}]"
ERROR="[${RED}ERROR${RESET}]"
WARN="[${YELLOW}WARN${RESET}]"
function INFO() {
    echo -e "${INFO} ${1}"
}
function ERROR() {
    echo -e "${ERROR} ${1}"
}
function WARN() {
    echo -e "${WARN} ${1}"
}

function SEPARATOR() {
    echo -e "${INFO}${BOLD}${LIGHT_BLUE}======================== ${1} ========================${RESET}"
}

save_path="/data/uptime"
mkdir -p $save_path
#url="https://raw.githubusercontent.com/louislam/uptime-kuma/master/compose.yaml"
UPTIME_PORT=3001

function CHECK_OS() {
SEPARATOR "检查环境"
OSVER=$(cat /etc/os-release | grep -o '[0-9]' | head -n 1)

if [ -f /etc/os-release ]; then
    . /etc/os-release
else
    echo "无法确定发行版"
    exit 1
fi

case "$ID" in
    "centos")
        repo_type="centos"
        ;;
    "debian")
        repo_type="debian"
        ;;
    "rhel")
        repo_type="rhel"
        ;;
    "ubuntu")
        repo_type="ubuntu"
        ;;
    "opencloudos")
        repo_type="centos"
        ;;
    "rocky")
        repo_type="centos"
        ;;
    *)
        WARN "此脚本目前不支持您的系统: $ID"
        exit 1
        ;;
esac

INFO "System release:: $NAME"
INFO "System version: $VERSION"
INFO "System ID: $ID"
INFO "System ID Like: $ID_LIKE"
}

function CHECK_PACKAGE_MANAGER() {
    if command -v dnf &> /dev/null; then
        package_manager="dnf"
    elif command -v yum &> /dev/null; then
        package_manager="yum"
    elif command -v apt-get &> /dev/null; then
        package_manager="apt-get"
    elif command -v apt &> /dev/null; then
        package_manager="apt"
    else
        ERROR "不受支持的软件包管理器."
        exit 1
    fi
}

function CHECK_PKG_MANAGER() {
    if command -v rpm &> /dev/null; then
        pkg_manager="rpm"
    elif command -v dpkg &> /dev/null; then
        pkg_manager="dpkg"
    elif command -v apt &> /dev/null; then
        pkg_manager="apt"
    else
        ERROR "无法确定包管理系统."
        exit 1
    fi
}

function CHECKMEM() {
memory_usage=$(free | awk '/^Mem:/ {printf "%.2f", $3/$2 * 100}')
memory_usage=${memory_usage%.*}

if [[ $memory_usage -gt 90 ]]; then
    read -e -p "$(WARN "内存占用率${LIGHT_RED}高于 70%($memory_usage%)${RESET} 是否继续安装? ${PROMPT_YES_NO}")" continu
    if [ "$continu" == "n" ] || [ "$continu" == "N" ]; then
        exit 1
    fi
else
    INFO "内存资源充足.请继续 ${LIGHT_GREEN}($memory_usage%)${RESET}"
fi
}

function CHECKFIRE() {
systemctl stop firewalld &> /dev/null
systemctl disable firewalld &> /dev/null
systemctl stop iptables &> /dev/null
systemctl disable iptables &> /dev/null
ufw disable &> /dev/null
INFO "防火墙已被禁用."

if [[ "$repo_type" == "centos" || "$repo_type" == "rhel" ]]; then
    if sestatus | grep "SELinux status" | grep -q "enabled"; then
        WARN "SELinux 已启用。禁用 SELinux..."
        setenforce 0
        sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
        INFO "SELinux 已被禁用."
    else
        INFO "SELinux 已被禁用."
    fi
fi
}


function INSTALL_PACKAGE(){
SEPARATOR "安装依赖"
INFO "检查依赖安装情况，请稍等 ..."
TIMEOUT=300
PACKAGES_APT=(
    lsof jq wget apache2-utils tar
)
PACKAGES_YUM=(
    epel-release lsof jq wget yum-utils httpd-tools tar
)

if [ "$package_manager" = "dnf" ] || [ "$package_manager" = "yum" ]; then
    for package in "${PACKAGES_YUM[@]}"; do
        if $pkg_manager -q "$package" &>/dev/null; then
            INFO "${LIGHT_GREEN}已经安装${RESET} $package ..."
        else
            INFO "${LIGHT_CYAN}正在安装${RESET} $package ..."

            start_time=$(date +%s)

            $package_manager -y install "$package" --skip-broken > /dev/null 2>&1 &
            install_pid=$!

            while [[ $(($(date +%s) - $start_time)) -lt $TIMEOUT ]] && kill -0 $install_pid &>/dev/null; do
                sleep 1
            done

            if kill -0 $install_pid &>/dev/null; then
                WARN "$package 的安装时间超过 ${LIGHT_YELLOW}$TIMEOUT 秒${RESET}。是否继续? [${LIGHT_GREEN}y${RESET}/${LIGHT_YELLOW}n${RESET}]"
                read -r continue_install
                if [ "$continue_install" != "y" ]; then
                    ERROR "$package 的安装超时。退出脚本。"
                    exit 1
                else
                    continue
                fi
            fi

            wait $install_pid
            if [ $? -ne 0 ]; then
                ERROR "$package 安装失败。请检查系统安装源，然后再次运行此脚本！请尝试手动执行安装: ${LIGHT_BLUE}$package_manager -y install $package${RESET}"
                exit 1
            fi
        fi
    done
elif [ "$package_manager" = "apt-get" ] || [ "$package_manager" = "apt" ];then
    dpkg --configure -a &>/dev/null
    $package_manager update &>/dev/null
    for package in "${PACKAGES_APT[@]}"; do
        if $pkg_manager -s "$package" &>/dev/null; then
            INFO "已经安装 $package ..."
        else
            INFO "正在安装 $package ..."
            $package_manager install -y $package > /dev/null 2>&1
            if [ $? -ne 0 ]; then
                ERROR "安装 $package 失败,请检查系统安装源之后再次运行此脚本！请尝试手动执行安装: ${LIGHT_BLUE}$package_manager -y install $package${RESET}"
                exit 1
            fi
        fi
    done
else
    ERROR "无法确定包管理系统,脚本无法继续执行,请检查!"
    exit 1
fi
}


function CHECK_DOCKER() {
status=$(systemctl is-active docker)

if [ "$status" = "active" ]; then
    INFO "Docker 服务运行正常，请继续..."
else
    ERROR "Docker 服务未运行，会导致服务无法正常安装运行，请检查后再次执行脚本！"
    ERROR "-----------服务启动失败，请查看错误日志 ↓↓↓-----------"
      journalctl -u docker.service --no-pager
    ERROR "-----------服务启动失败，请查看错误日志 ↑↑↑-----------"
    exit 1
fi
}


function INSTALL_DOCKER() {
SEPARATOR "安装Docker"
repo_file="docker-ce.repo"
url="https://download.docker.com/linux/$repo_type"
MAX_ATTEMPTS=3
attempt=0
success=false

if [ "$repo_type" = "centos" ] || [ "$repo_type" = "rhel" ]; then
    if ! command -v docker &> /dev/null;then
      while [[ $attempt -lt $MAX_ATTEMPTS ]]; do
        attempt=$((attempt + 1))
        WARN "Docker 未安装，正在进行安装..."
        yum-config-manager --add-repo $url/$repo_file &>/dev/null
        $package_manager -y install docker-ce &>/dev/null
        if [ $? -eq 0 ]; 键，然后
            success=true
            break
        fi
        ERROR "Docker 安装失败，正在尝试重新下载 (尝试次数: $attempt)"
      done

      if $success; then
         INFO "Docker 安装成功，版本为：$(docker --version)"
         systemctl restart docker &>/dev/null
         CHECK_DOCKER
         systemctl enable docker &>/dev/null
      else
         ERROR "Docker 安装失败，请尝试手动安装"
         exit 1
      fi
    else
      INFO "Docker 已安装，安装版本为：$(docker --version)"
      systemctl restart docker | grep -E "ERROR|ELIFECYCLE|WARN"
    fi
elif [ "$repo_type" == "ubuntu" ]; then
    if ! command -v docker &> /dev/null;then
      while [[ $attempt -lt $MAX_ATTEMPTS ]]; do
        attempt=$((attempt + 1))
        WARN "Docker 未安装，正在进行安装..."
        curl -fsSL $url/gpg | sudo apt-key add - &>/dev/null
        add-apt-repository "deb [arch=amd64] $url $(lsb_release -cs) stable" <<< $'\n' &>/dev/null
        $package_manager -y install docker-ce docker-ce-cli containerd.io &>/dev/null
        if [ $? -eq 0 ]; 键，然后
            success=true
            break
        fi
        ERROR "Docker 安装失败，正在尝试重新下载 (尝试次数: $attempt)"
      done

      if $success; then
         INFO "Docker 安装成功，版本为：$(docker --version)"
         systemctl restart docker &>/dev/null
         CHECK_DOCKER
         systemctl enable docker &>/dev/null
      else
         ERROR "Docker 安装失败，请尝试手动安装"
         exit 1
      fi
    else
      INFO "Docker 已安装，安装版本为：$(docker --version)"
      systemctl restart docker | grep -E "ERROR|ELIFECYCLE|WARN"
    fi
elif [ "$repo_type" == "debian" ]; then
    if ! command -v docker &> /dev/null;then
      while [[ $attempt -lt $MAX_ATTEMPTS ]]; do
        attempt=$((attempt + 1))

        WARN "Docker 未安装，正在进行安装..."
        curl -fsSL $url/gpg | sudo apt-key add - &>/dev/null
        add-apt-repository "deb [arch=amd64] $url $(lsb_release -cs) stable" <<< $'\n' &>/dev/null
        $package_manager -y install docker-ce docker-ce-cli containerd.io &>/dev/null
        if [ $? -eq 0 ]; then
            success=true
            break
        fi
        ERROR "Docker 安装失败，正在尝试重新下载 (尝试次数: $attempt)"
      done

      if $success; then
         INFO "Docker 安装成功，版本为：$(docker --version)"
         systemctl restart docker &>/dev/null
         CHECK_DOCKER
         systemctl enable docker &>/dev/null
      else
         ERROR "Docker 安装失败，请尝试手动安装"
         exit 1
      fi
    else
        INFO "Docker 已安装，安装版本为：$(docker --version)"
        systemctl restart docker &>/dev/null
        CHECK_DOCKER
    fi
else
    ERROR "不支持的操作系统."
    exit 1
fi
}

# 安装完成之后打印提示信息
function PROMPT(){
INFO
INFO "=================感谢您的耐心等待，安装已经完成=================="
# 获取公网IP
PUBLIC_IP=$(curl -s ip.sb)

# 获取所有网络接口的IP地址
ALL_IPS=$(hostname -I)

# 排除不需要的地址（127.0.0.1和docker0）
INTERNAL_IP=$(echo "$ALL_IPS" | awk '$1!="127.0.0.1" && $1!="::1" && $1!="docker0" {print $1}')
INFO
INFO "请用浏览器访问面板: "
INFO "公网访问地址: http://$PUBLIC_IP:${UPTIME_PORT}"
INFO "内网访问地址: http://$INTERNAL_IP:${UPTIME_PORT}"
INFO
INFO "作者博客: https://dqzboy.com"
INFO  
INFO "如果使用的是云服务器，请至安全组开放 ${UPTIME_PORT} 端口"
INFO
INFO "================================================================"
}

function INSTALL_SERVER() {
SEPARATOR "开始安装"

# 确保目录存在
if [ ! -d "$save_path" ]; then
    mkdir -p $save_path
    INFO "创建目录: $save_path"
fi

cd $save_path || {
    ERROR "无法进入目录: $save_path"
    exit 1
}

# 提示输入端口
read -e -p "$(INFO "请输入 uptime-kuma 访问端口 (默认: 3001): ")" UPTIME_PORT
UPTIME_PORT=${UPTIME_PORT:-3001}
INFO "使用端口: ${UPTIME_PORT}"

# 创建 docker-compose.yaml 文件
INFO "正在创建配置文件..."
cat > $save_path/docker-compose.yaml <<EOF
services:
  uptime-kuma:
    container_name: uptime-kuma
    image: louislam/uptime-kuma:2
    restart: unless-stopped
    volumes:
      - ./data:/app/data
    ports:
      # <Host Port>:<Container Port>
      - "${UPTIME_PORT}:3001"
EOF

if [ $? -eq 0 ]; then
    INFO "配置文件创建成功"
else
    ERROR "配置文件创建失败"
    exit 1
fi

# 验证文件是否存在且不为空
if [ ! -s "$save_path/docker-compose.yaml" ]; then
    ERROR "docker-compose.yaml 文件为空或不存在"
    exit 1
fi

#启动 Docker容器
INFO "正在启动 Docker 容器..."
cd $save_path
docker compose up -d

if [ $? -ne 0 ]; then
    ERROR "Docker compose 启动失败，请查看上方错误信息"
    ERROR "可以尝试手动执行: cd $save_path && docker compose up -d"
    exit 1
fi

# 等待容器启动
INFO "等待容器启动..."
sleep 5

#检查 uptime-kuma容器状态
for i in {1..10}; do
    status_uptime=`docker container inspect -f '{{.State.Running}}' uptime-kuma 2>/dev/null`
    if [[ "$status_uptime" == "true" ]]; then
        break
    fi
    sleep 1
done

#判断容器状态并打印提示
if [[ "$status_uptime" == "true" ]]; then
    INFO "容器启动成功！"
    #调用提示信息函数
    PROMPT
else
    ERROR "容器启动超时，请检查容器状态"
    ERROR "查看容器状态: docker ps -a"
    ERROR "查看日志: docker compose logs -f"
    exit 1
fi
}

function UNISTALL_SERVER() {
#卸载 uptime-kuma
if docker ps -a --format "{{.Names}}" | grep -q "uptime-kuma"; then
    cd $save_path || {
        ERROR "无法进入目录: $save_path"
        exit 1
    }
    docker compose down
    INFO "uptime-kuma 已成功卸载。"
else
    WARN "没有找到 uptime-kuma容器，无需卸载"
fi
}

function UPDATE_SERVER() {
#升级 uptime-kuma
if docker ps -a --format "{{.Names}}" | grep -q "uptime-kuma"; then
    cd $save_path || {
        ERROR "无法进入目录: $save_path"
        exit 1
    }
    INFO "正在拉取最新镜像..."
    docker compose pull
    INFO "正在重新创建容器..."
    docker compose up -d --force-recreate
    INFO "uptime-kuma已成功升级。"
else
    WARN "没有找到 uptime-kuma容器，无法执行升级操作"
fi
}

function RESTART_SERVER() {
#重启 uptime-kuma
if docker ps -a --format "{{.Names}}" | grep -q "uptime-kuma"; then
    cd $save_path || {
        ERROR "无法进入目录: $save_path"
        exit 1
    }
    INFO "正在重启 uptime-kuma 服务..."
    docker compose restart
    INFO "uptime-kuma已成功重启。"
else
    WARN "没有找到 uptime-kuma容器，无法执行重启操作"
fi
}

function STOP_SERVER() {
#停止 uptime-kuma
if docker ps -a --format "{{.Names}}" | grep -q "uptime-kuma"; then
    cd $save_path || {
        ERROR "无法进入目录: $save_path"
        exit 1
    }
    INFO "正在停止 uptime-kuma 服务..."
    docker compose stop
    INFO "uptime-kuma已成功停止。"
else
    WARN "没有找到 uptime-kuma容器，无法执行停止操作"
fi
}


function main_menu() {
SEPARATOR "请选择操作"
echo -e "1) ${BOLD}${LIGHT_GREEN}安装${RESET}服务"
echo -e "2) ${BOLD}${LIGHT_YELLOW}更新${RESET}服务"
echo -e "3) ${BOLD}${LIGHT_BLUE}重启${RESET}服务"
echo -e "4) ${BOLD}${LIGHT_RED}停止${RESET}服务"
echo -e "5) ${BOLD}${LIGHT_MAGENTA}卸载${RESET}服务"
echo -e "0) ${BOLD}退出脚本${RESET}"
echo "---------------------------------------------------------------"
read -e -p "$(INFO "输入${LIGHT_CYAN}对应数字${RESET}并按${LIGHT_GREEN}Enter${RESET}键 > ")" main_choice


case $main_choice 在
    1)
        CHECK_OS
        CHECK_PACKAGE_MANAGER
        CHECK_PKG_MANAGER
        CHECKMEM
        INSTALL_PACKAGE
        INSTALL_DOCKER
        INSTALL_SERVER
        ;;
    2)
        UPDATE_SERVER
        ;;
    3)
        RESTART_SERVER
        ;;
    4)
        STOP_SERVER
        ;;
    5)
        UNISTALL_SERVER
        ;;
    0)
        exit 1
        ;;
    *)
        WARN "输入了无效的选择。请重新${LIGHT_GREEN}选择0-5${RESET}的选项."
        sleep 2; main_menu
        ;;
esac
}
main_menu
