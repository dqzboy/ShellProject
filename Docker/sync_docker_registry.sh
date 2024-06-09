#!/usr/bin/env bash
#===============================================================================
#
#          FILE: sync_registry-ui.sh
# 
#         USAGE: ./sync_registry-ui.sh
#
#   DESCRIPTION: 镜像同步脚本。将某一个镜像TAG下所有平台的镜像推送到指定的镜像仓库下
# 
#  ORGANIZATION: DingQz dqzboy.com 浅时光博客
#===============================================================================

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

# 设置源镜像仓库和标签
SRC_REPO="dqzboy/A"
SRC_TAG="latest"

# 设置目标镜像仓库和标签
DEST_REPO="dqzboy/B"
DEST_TAG="latest"

# 定义需要拉取的平台列表
PLATFORMS=("linux/386" "linux/amd64" "linux/arm/v6" "linux/arm/v7" "linux/arm64" "linux/ppc64le" "linux/s390x")

# 首先，确保登录到Docker Hub
INFO "登录到Docker Hub..."
docker login

# 拉取所有平台的镜像并创建多平台镜像
INFO "拉取源镜像并创建多平台镜像..."
docker buildx create --use
docker buildx imagetools create -t "$DEST_REPO:$DEST_TAG" "$SRC_REPO:$SRC_TAG"

# 推送多平台镜像到Docker Hub
INFO "推送多平台镜像到Docker Hub..."
docker buildx imagetools inspect "$DEST_REPO:$DEST_TAG"

INFO "所有指定平台的镜像已成功拉取、标记并推送。"
echo
INFO "=================感谢您的耐心等待，同步已经完成=================="
INFO
INFO "请用浏览器访问Docker Hub官网: "
INFO "访问地址: https://hub.docker.com/repository/docker/$DEST_REPO"
INFO
INFO "作者博客: https://dqzboy.com"
INFO "技术交流: https://t.me/dqzboyblog"
INFO "代码仓库: https://github.com/dqzboy"
INFO  
INFO
INFO "================================================================"
