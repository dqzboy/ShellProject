#!/usr/bin/env bash
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



function INSTALL_DOCKER_CN() {
MAX_ATTEMPTS=3
attempt=0
success=false
cpu_arch=$(uname -m)
save_path="/opt/docker_tgz"
mkdir -p $save_path
docker_ver="docker-26.1.4.tgz"

case $cpu_arch in
  "arm64")
    url="https://gitlab.com/dqzboy/docker/-/raw/main/stable/aarch64/$docker_ver"
    ;;
  "aarch64")
    url="https://gitlab.com/dqzboy/docker/-/raw/main/stable/aarch64/$docker_ver"
    ;;
  "x86_64")
    url="https://gitlab.com/dqzboy/docker/-/raw/main/stable/x86_64/$docker_ver"
    ;;
  *)
    ERROR "不支持的CPU架构: $cpu_arch"
    exit 1
    ;;
esac


if ! command -v docker &> /dev/null; then
  while [ $attempt -lt $MAX_ATTEMPTS ]; do
    attempt=$((attempt + 1))
    WARN "Docker 未安装，正在进行安装..."
    wget -P "$save_path" "$url" &>/dev/null
    if [ $? -eq 0 ]; then
        success=true
        break
    fi
    ERROR "Docker 安装失败，正在尝试重新下载 (尝试次数: $attempt)"
  done

  if $success; then
     tar -xzf $save_path/$docker_ver -C $save_path
     \cp $save_path/docker/* /usr/bin/
     rm -rf $save_path
     INFO "Docker 安装成功，版本为：$(docker --version)"
     
     cat > /usr/lib/systemd/system/docker.service <<EOF
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target firewalld.service
Wants=network-online.target
[Service]
Type=notify
ExecStart=/usr/bin/dockerd
ExecReload=/bin/kill -s HUP 
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TimeoutStartSec=0
Delegate=yes
KillMode=process
Restart=on-failure
StartLimitBurst=3
StartLimitInterval=60s
[Install]
WantedBy=multi-user.target
EOF
     systemctl daemon-reload
     systemctl restart docker | grep -E "ERROR|ELIFECYCLE|WARN"
     systemctl enable docker &>/dev/null
  else
     ERROR "Docker 安装失败，请尝试手动安装"
     exit 1
  fi
else 
  INFO "Docker 已安装，安装版本为：$(docker --version)"
  systemctl restart docker | grep -E "ERROR|ELIFECYCLE|WARN"
fi
}


function INSTALL_COMPOSE_CN() {
TAG=`curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r '.tag_name'`
MAX_ATTEMPTS=3
attempt=0
cpu_arch=$(uname -m)
success=false
save_path="/usr/local/lib/docker/cli-plugins"
mkdir -p $save_path

case $cpu_arch in
  "arm64")
    url="https://gitlab.com/dqzboy/docker/-/raw/main/stable/aarch64/docker-compose-linux-aarch64"
    ;;
  "aarch64")
    url="https://gitlab.com/dqzboy/docker/-/raw/main/stable/aarch64/docker-compose-linux-aarch64"
    ;;
  "x86_64")
    url="https://gitlab.com/dqzboy/docker/-/raw/main/stable/x86_64/docker-compose-linux-x86_64"
    ;;
  *)
    ERROR "不支持的CPU架构: $cpu_arch"
    exit 1
    ;;
esac



chmod +x /usr/local/lib/docker/cli-plugins/docker-compose &>/dev/null
if ! command -v docker compose &> /dev/null || [ -z "$(docker compose --version)" ]; then
    WARN "Docker Compose 未安装或安装不完整，正在进行安装..."    
    while [ $attempt -lt $MAX_ATTEMPTS ]; do
        attempt=$((attempt + 1))
        curl -SL $url -o $save_path/docker-compose &>/dev/null
        chmod +x /usr/local/lib/docker/cli-plugins/docker-compose &>/dev/null
        if [ $? -eq 0 ]; then
            version_check=$(docker compose version)
            if [ -n "$version_check" ]; then
                success=true
                chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
                break
            else
                ERROR "Docker Compose下载的文件不完整，正在尝试重新下载 (尝试次数: $attempt)"
                rm -f /usr/local/lib/docker/cli-plugins/docker-compose &>/dev/null
            fi
        fi

        ERROR "Docker Compose 下载失败，正在尝试重新下载 (尝试次数: $attempt)"
    done

    if $success; then
        INFO "Docker Compose 安装成功，版本为：$(docker compose version)"
    else
        ERROR "Docker Compose 下载失败，请尝试手动安装docker-compose"
        exit 1
    fi
else
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    INFO "Docker Compose 已安装，安装版本为：$(docker compose version)"
fi
}

INSTALL_DOCKER_CN
INSTALL_COMPOSE_CN
