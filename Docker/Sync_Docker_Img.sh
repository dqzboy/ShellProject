#!/usr/bin/env bash
#===============================================================================
#
#          FILE: sync_docker_img.sh
# 
#         USAGE: ./sync_docker_img.sh
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


function SYNC_IMAGE() {
# 首先，确保登录到Docker Hub
INFO "登录到Docker Hub..."
DOCKER_USERNAME="dqzboy"
DOCKER_PASSWORD="dingqz19970323."

#执行docker login
echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin

#检查登录是否成功
if [ $? -eq 0 ]; then
    INFO "Docker login successful."
else
    INFO "Docker login failed."
    exit 1
fi

# 设置源镜像仓库和标签
SRC_REPO="nginx"
SRC_TAG="latest"

# 设置目标镜像仓库和标签
DEST_REPO="dqzboy/nginx"
DEST_TAG="latest"

# 定义需要拉取的平台列表
PLATFORMS=("linux/amd64" "linux/arm/v6" "linux/arm/v7" "linux/arm64" "linux/ppc64le" "linux/s390x")


# 检查本地是否存在源镜像
FORCE_UPDATE=false
if ! docker image inspect $SRC_REPO:$SRC_TAG &>/dev/null; then
  WARN "源镜像在本地不存在，正在拉取..."
  docker pull $SRC_REPO:$SRC_TAG
  FORCE_UPDATE=true
fi

CURRENT_VERSION=$(docker image inspect $SRC_REPO:$SRC_TAG --format='{{index .RepoDigests 0}}' | grep -o 'sha256:[^"]*')
LATEST_VERSION=$(curl -s --max-time 60 "https://registry.hub.docker.com/v2/repositories/$SRC_REPO/tags/$SRC_TAG" | jq -r '.digest')

if [[ -n $CURRENT_VERSION && -n $LATEST_VERSION ]]; then
  if [ "$CURRENT_VERSION" != "$LATEST_VERSION" ] || [ "$FORCE_UPDATE" = true ]; then
    INFO "镜像已更新或需要强制更新，进行镜像同步操作..."
    # 拉取源镜像仓库所有平台的镜像并创建多平台镜像
    INFO "拉取源镜像并创建多平台镜像..."
    docker buildx create --use
    docker buildx imagetools create -t "$DEST_REPO:$DEST_TAG" "$SRC_REPO:$SRC_TAG"

    # 推送多平台镜像到Docker Hub
    INFO "推送多平台镜像到Docker Hub..."
    docker buildx imagetools inspect "$DEST_REPO:$DEST_TAG"

    INFO "所有指定平台的镜像已成功拉取、标记并推送。"
    docker rmi $(docker images -q --filter "dangling=true" --filter "reference=$SRC_REPO") &>/dev/null
  else
    WARN "镜像无需更新"
    read -e -p "是否要强制推送镜像? [y/n]: " force_push
    if [[ "$force_push" == "y" || "$force_push" == "Y" ]]; then
      INFO "强制进行镜像同步操作..."
      # 拉取源镜像仓库所有平台的镜像并创建多平台镜像
      INFO "拉取源镜像并创建多平台镜像..."
      docker buildx create --use
      docker buildx imagetools create -t "$DEST_REPO:$DEST_TAG" "$SRC_REPO:$SRC_TAG"

      # 推送多平台镜像到Docker Hub
      INFO "推送多平台镜像到Docker Hub..."
      docker buildx imagetools inspect "$DEST_REPO:$DEST_TAG"

      INFO "所有指定平台的镜像已成功拉取、标记并推送。"
      docker rmi $(docker images -q --filter "dangling=true" --filter "reference=$SRC_REPO") &>/dev/null
    else
      WARN "用户选择不强制推送镜像。"
    fi
  fi
else
  ERROR "获取Images ID失败，无法进行同步，请稍后再试！"
  exit 1
fi

}


function PROMPT(){
INFO
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

}

main() {
  SYNC_IMAGE
  PROMPT
}
main
