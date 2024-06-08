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


function CHECK_OS() {
INFO "======================= 检查环境 ======================="
if [ -f /etc/os-release ]; then
    . /etc/os-release
else
    ERROR "无法确定发行版"
    exit 1
fi


# 根据发行版选择存储库类型
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
        WARN "此脚本暂不支持您的系统: $ID"
        exit 1
        ;;
esac

INFO "系统发行版: $NAME"
INFO "系统版本: $VERSION"
INFO "系统ID: $ID"
INFO "系统ID Like: $ID_LIKE"
}


function INSTALL_DOCKER() {
# 定义存储库文件名
repo_file="docker-ce.repo"
# 下载存储库文件
url="https://download.docker.com/linux/$repo_type"

# 定义最多重试次数
MAX_ATTEMPTS=3
# 初始化 attempt和 success变量为0和 false
attempt=0
success=false

if [ "$repo_type" = "centos" ] || [ "$repo_type" = "rhel" ]; then
    if ! command -v docker &> /dev/null;then
      while [[ $attempt -lt $MAX_ATTEMPTS ]]; do
        attempt=$((attempt + 1))
        ERROR "docker 未安装，正在进行安装..."
        yum-config-manager --add-repo $url/$repo_file &>/dev/null
        yum -y install docker-ce &>/dev/null
        # 检查命令的返回值
        if [ $? -eq 0 ]; then
            success=true
            break
        fi
        ERROR "docker安装失败，正在尝试重新下载 (尝试次数: $attempt)"
      done

      if $success; then
         INFO "docker 安装版本为：$(docker --version)"
         systemctl restart docker | grep -E "ERROR|ELIFECYCLE|WARN"
         systemctl enable docker &>/dev/null
      else
         ERROR "docker安装失败，请尝试手动安装"
         exit 1
      fi
    else
      INFO "docker 已安装，安装版本为：$(docker --version)"
      systemctl restart docker | grep -E "ERROR|ELIFECYCLE|WARN"
    fi
elif [ "$repo_type" == "ubuntu" ]; then
    if ! command -v docker &> /dev/null;then
      while [[ $attempt -lt $MAX_ATTEMPTS ]]; do
        attempt=$((attempt + 1))
        ERROR "docker 未安装，正在进行安装..."
        curl -fsSL $url/gpg | sudo apt-key add - &>/dev/null
        add-apt-repository "deb [arch=amd64] $url $(lsb_release -cs) stable" <<< $'\n' &>/dev/null
        apt-get -y install docker-ce docker-ce-cli containerd.io &>/dev/null
        # 检查命令的返回值
        if [ $? -eq 0 ]; then
            success=true
            break
        fi
        ERROR "docker安装失败，正在尝试重新下载 (尝试次数: $attempt)"
      done

      if $success; then
         INFO "docker 安装版本为：$(docker --version)"
         systemctl restart docker | grep -E "ERROR|ELIFECYCLE|WARN"
         systemctl enable docker &>/dev/null
      else
         ERROR "docker安装失败，请尝试手动安装"
         exit 1
      fi
    else
      INFO "docker 已安装，安装版本为：$(docker --version)"
      systemctl restart docker | grep -E "ERROR|ELIFECYCLE|WARN"
    fi
elif [ "$repo_type" == "debian" ]; then
    if ! command -v docker &> /dev/null;then
      while [[ $attempt -lt $MAX_ATTEMPTS ]]; do
        attempt=$((attempt + 1))

        ERROR "docker 未安装，正在进行安装..."
        curl -fsSL $url/gpg | sudo apt-key add - &>/dev/null
        add-apt-repository "deb [arch=amd64] $url $(lsb_release -cs) stable" <<< $'\n' &>/dev/null
        apt-get -y install docker-ce docker-ce-cli containerd.io &>/dev/null
        # 检查命令的返回值
        if [ $? -eq 0 ]; then
            success=true
            break
        fi
        ERROR "docker安装失败，正在尝试重新下载 (尝试次数: $attempt)"
      done

      if $success; then
         INFO "docker 安装版本为：$(docker --version)"
         systemctl restart docker | grep -E "ERROR|ELIFECYCLE|WARN"
         systemctl enable docker &>/dev/null
      else
         ERROR "docker安装失败，请尝试手动安装"
         exit 1
      fi
    else
      INFO "docker 已安装，安装版本为：$(docker --version)"
      systemctl restart docker | grep -E "ERROR|ELIFECYCLE|WARN"
    fi
else
    ERROR "Unsupported operating system."
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

function ADD_UPTIME_KUMA() {
    INFO "=======================开始安装 ======================="
    read -e -p "$(INFO '是否部署或卸载 uptime-kuma监控工具？(部署请输入 y，卸载请输入 n): ')" uptime

    if [[ "$uptime" == "y" ]]; then
        #检查是否已经运行了 uptime-kuma容器
        if docker ps -a --format "{{.Names}}" | grep -q "uptime-kuma"; then
            WARN "已经运行了uptime-kuma监控工具。"
            read -e -p "$(WARN '是否停止和删除旧的容器并继续安装？(y/n): ')" continue_install

            if [[ "$continue_install" == "y" ]]; then
                docker stop uptime-kuma
                docker rm uptime-kuma
                WARN "已停止和删除旧的uptime-kuma容器。"
            else
                WARN "已取消部署uptime-kuma监控工具。"
                exit 0
            fi
        fi

        MAX_TRIES=3

        for ((try=1; try<=${MAX_TRIES}; try++)); do
            read -e -p "$(INFO '请输入监听的端口: ')" UPTIME_PORT

            #检查端口是否已被占用
            if ss -tulwn | grep -q ":${UPTIME_PORT} "; then
                ERROR "端口 ${UPTIME_PORT}已被占用，请尝试其他端口。"
                if [ "${try}" -lt "${MAX_TRIES}" ]; then
                    WARN "您还有 $((${MAX_TRIES} - ${try}))次尝试机会。"
                else
                    ERROR "您已用尽所有尝试机会。"
                    exit 1
                fi
            else
                break
            fi
        done

        #提示用户输入映射的目录
        read -e -p "$(INFO '请输入数据持久化在宿主机上的目录路径: ')" MAPPING_DIR
        #检查目录是否存在，如果不存在则创建
        if [ ! -d "${MAPPING_DIR}" ]; then
            mkdir -p "${MAPPING_DIR}"
            INFO "目录已创建：${MAPPING_DIR}"
        fi

        #启动 Docker容器
        docker run -d --restart=always -p "${UPTIME_PORT}":3001 -v "${MAPPING_DIR}":/app/data --name uptime-kuma louislam/uptime-kuma:1
        #检查 uptime-kuma容器状态
        status_uptime=`docker container inspect -f '{{.State.Running}}' uptime-kuma 2>/dev/null`

        #判断容器状态并打印提示
        if [[ "$status_uptime" == "true" ]]; then
            INFO ">>>>> Docker containers are up and running <<<<<"
            #调用提示信息函数
            PROMPT
        else
            ERROR ">>>>> The following containers are not up <<<<<"
            if [[ "$status_uptime" != "true" ]]; then
                ERROR "uptime-kuma安装过程中出现问题，请检查日志或手动验证容器状态。"
            fi
        fi
    elif [[ "$uptime" == "n" ]]; then
        #卸载 uptime-kuma
        if docker ps -a --format "{{.Names}}" | grep -q "uptime-kuma"; then
            docker stop uptime-kuma
            docker rm uptime-kuma
            INFO "uptime-kuma已成功卸载。"
        else
            WARN "没有找到 uptime-kuma容器，无需卸载。"
        fi
    else
        ERROR "选项错误！请重新运行脚本并选择正确的选项。"
        exit 1
    fi
}

main() {
  CHECK_OS
  INSTALL_DOCKER
  ADD_UPTIME_KUMA
}
main
