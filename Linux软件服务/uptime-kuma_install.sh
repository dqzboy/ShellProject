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


function CHECK_OS() {
if [ -f /etc/os-release ]; then
    . /etc/os-release
else
    echo "无法确定发行版"
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

echo "------------------------------------------"
echo "系统发行版: $NAME"
echo "系统版本: $VERSION"
echo "系统ID: $ID"
echo "系统ID Like: $ID_LIKE"
echo "------------------------------------------"
}


function INSTALL_DOCKER() {
# 定义存储库文件名
repo_file="docker-ce.repo"
# 下载存储库文件
url="https://download.docker.com/linux/$repo_type"

if [ "$repo_type" = "centos" ] || [ "$repo_type" = "rhel" ]; then
    if ! command -v docker &> /dev/null;then
      while [ $attempt -lt $MAX_ATTEMPTS ]; do
        attempt=$((attempt + 1))
        ERROR "docker 未安装，正在进行安装..."
        yum-config-manager --add-repo $url/$repo_file &>/dev/null
        yum -y install docker-ce &>/dev/null
        # 检查命令的返回值
        if [ $? -eq 0 ]; then
            success=true
            break
        fi
        echo "docker安装失败，正在尝试重新下载 (尝试次数: $attempt)"
      done

      if $success; then
         SUCCESS1 ">>> $(docker --version)"
         systemctl restart docker | grep -E "ERROR|ELIFECYCLE|WARN"
         systemctl enable docker &>/dev/null
      else
         ERROR "docker安装失败，请尝试手动安装"
         exit 1
      fi
    else
      INFO1 "docker 已安装..."
      SUCCESS1 ">>> $(docker --version)"
      systemctl restart docker | grep -E "ERROR|ELIFECYCLE|WARN"
    fi
elif [ "$repo_type" == "ubuntu" ]; then
    if ! command -v docker &> /dev/null;then
      while [ $attempt -lt $MAX_ATTEMPTS ]; do
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
        echo "docker安装失败，正在尝试重新下载 (尝试次数: $attempt)"
      done

      if $success; then
         SUCCESS1 ">>> $(docker --version)"
         systemctl restart docker | grep -E "ERROR|ELIFECYCLE|WARN"
         systemctl enable docker &>/dev/null
      else
         ERROR "docker安装失败，请尝试手动安装"
         exit 1
      fi
    else
      INFO1 "docker 已安装..."
      SUCCESS1 ">>> $(docker --version)"
      systemctl restart docker | grep -E "ERROR|ELIFECYCLE|WARN"
    fi
elif [ "$repo_type" == "debian" ]; then
    if ! command -v docker &> /dev/null;then
      while [ $attempt -lt $MAX_ATTEMPTS ]; do
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
        echo "docker安装失败，正在尝试重新下载 (尝试次数: $attempt)"
      done

      if $success; then
         SUCCESS1 ">>> $(docker --version)"
         systemctl restart docker | grep -E "ERROR|ELIFECYCLE|WARN"
         systemctl enable docker &>/dev/null
      else
         ERROR "docker安装失败，请尝试手动安装"
         exit 1
      fi
    else
      INFO1 "docker 已安装..."
      SUCCESS1 ">>> $(docker --version)"
      systemctl restart docker | grep -E "ERROR|ELIFECYCLE|WARN"
    fi
else
    ERROR "Unsupported operating system."
    exit 1
fi
}

function ADD_UPTIME_KUMA() {
    SUCCESS "Uptime Kuma"
    read -e -p "$(echo -e ${GREEN}"是否部署uptime-kuma监控工具？(y/n): "${RESET})" uptime

    if [[ "$uptime" == "y" ]]; then
        # 检查是否已经运行了 uptime-kuma 容器
        if docker ps -a --format "{{.Names}}" | grep -q "uptime-kuma"; then
            WARN "已经运行了uptime-kuma监控工具。"
            read -e -p "$(echo -e ${GREEN}"是否停止和删除旧的容器并继续安装？(y/n): "${RESET})" continue_install

            if [[ "$continue_install" == "y" ]]; then
                docker stop uptime-kuma
                docker rm uptime-kuma
                INFO1 "已停止和删除旧的uptime-kuma容器。"
            else
                INFO1 "已取消部署uptime-kuma监控工具。"
                exit 0
            fi
        fi

        MAX_TRIES=3

        for ((try=1; try<=${MAX_TRIES}; try++)); do
            read -e -p "$(echo -e ${GREEN}"请输入监听的端口: "${RESET})" UPTIME_PORT

            # 检查端口是否已被占用
            if ss -tulwn | grep -q ":${UPTIME_PORT} "; then
                ERROR "端口 ${UPTIME_PORT} 已被占用，请尝试其他端口。"
                if [ "${try}" -lt "${MAX_TRIES}" ]; then
                    WARN "您还有 $((${MAX_TRIES} - ${try})) 次尝试机会。"
                else
                    ERROR "您已用尽所有尝试机会。"
                    exit 1
                fi
            else
                break
            fi
        done

        # 提示用户输入映射的目录
        read -e -p "$(echo -e ${GREEN}"请输入数据持久化在宿主机上的目录路径: "${RESET})" MAPPING_DIR
        # 检查目录是否存在，如果不存在则创建
        if [ ! -d "${MAPPING_DIR}" ]; then
            mkdir -p "${MAPPING_DIR}"
            INFO1 "目录已创建：${MAPPING_DIR}"
        fi

        # 启动 Docker 容器
        docker run -d --restart=always -p "${UPTIME_PORT}":3001 -v "${MAPPING_DIR}":/app/data --name uptime-kuma louislam/uptime-kuma:1
        # 检查 uptime-kuma 容器状态
        status_uptime=`docker container inspect -f '{{.State.Running}}' uptime-kuma 2>/dev/null`

        # 判断容器状态并打印提示
        if [[ "$status_uptime" == "true" ]]; then
            SUCCESS "CHECK"
            Progress
            SUCCESS1 ">>>>> Docker containers are up and running."
            INFO1 "uptime-kuma 安装完成，请使用浏览器访问 IP:${UPTIME_PORT} 进行访问。"
        else
            SUCCESS "CHECK"
            Progress
            ERROR ">>>>> The following containers are not up"
            if [[ "$status_uptime" != "true" ]]; then
                ERROR "uptime-kuma 安装过程中出现问题，请检查日志或手动验证容器状态。"
            fi
        fi
    elif [[ "$uptime" == "n" ]]; then
        # 取消部署uptime-kuma
        WARN "已取消部署uptime-kuma监控工具！"
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
