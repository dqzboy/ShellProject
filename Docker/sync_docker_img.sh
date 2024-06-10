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
# 输入docker登入的账号密码
export DOCKER_USERNAME="your_username"
export DOCKER_PASSWORD="your_password"

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
SRC_REPO="joxit/docker-registry-ui"
SRC_TAG="main"

# 设置目标镜像仓库和标签
DEST_REPO="dqzboy/docker-registry-ui"
DEST_TAG="latest"

# 定义需要拉取的平台列表
PLATFORMS=("linux/386" "linux/amd64" "linux/arm/v6" "linux/arm/v7" "linux/arm64" "linux/ppc64le" "linux/s390x")


CURRENT_VERSION=$(docker image inspect $SRC_REPO:$SRC_TAG --format='{{index .RepoDigests 0}}' | grep -o 'sha256:[^"]*')
LATEST_VERSION=$(curl -s --max-time 60 "https://registry.hub.docker.com/v2/repositories/$SRC_REPO/tags/$SRC_TAG" | jq -r '.digest')

if [[ -n $CURRENT_VERSION && -n $LATEST_VERSION ]]; then
  if [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
    INFO "docker-registry-ui 镜像已更新，进行镜像同步操作..."
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
    WARN "docker-registry-ui 镜像无需更新"
  fi
else
  ERROR "获取Images ID失败，无法进行同步，请稍后再试！"
  exit 1
fi
}


function ADD_CRON() {
INFO "======================= 定时任务 ======================="
read -e -p "$(INFO '是否加入定时更新镜像？(y/n): ')" cron
if [[ "$cron" == "y" ]]; then
mkdir -p /opt/script/syncimage

# 定时任务更新镜像脚本顺利执行的前提是本地需要有源镜像的存在
cat > /opt/script/syncimage/SyncImage.sh << \EOF
#!/usr/bin/env bash
# 输入docker登入的账号密码
export DOCKER_USERNAME="your_username"
export DOCKER_PASSWORD="your_password"

#执行docker login
echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin

#检查登录是否成功
if [ $? -eq 0 ]; then
    echo "Docker login successful."
else
    echo "Docker login failed."
    exit 1
fi

# 设置源镜像仓库和标签
SRC_REPO="joxit/docker-registry-ui"
SRC_TAG="main"

# 设置目标镜像仓库和标签
DEST_REPO="dqzboy/docker-registry-ui"
DEST_TAG="latest"

# 定义需要拉取的平台列表
PLATFORMS=("linux/386" "linux/amd64" "linux/arm/v6" "linux/arm/v7" "linux/arm64" "linux/ppc64le" "linux/s390x")

CURRENT_VERSION=$(docker image inspect $SRC_REPO:$SRC_TAG --format='{{index .RepoDigests 0}}' | grep -o 'sha256:[^"]*')
LATEST_VERSION=$(curl -s --max-time 60 "https://registry.hub.docker.com/v2/repositories/$SRC_REPO/tags/$SRC_TAG" | jq -r '.digest')

if [[ -n $CURRENT_VERSION && -n $LATEST_VERSION ]]; then
  if [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
    echo "docker-registry-ui 镜像已更新，进行镜像同步操作..."
    docker buildx create --use
    docker buildx imagetools create -t "$DEST_REPO:$DEST_TAG" "$SRC_REPO:$SRC_TAG"
    docker buildx imagetools inspect "$DEST_REPO:$DEST_TAG"
    docker rmi $(docker images -q --filter "dangling=true" --filter "reference=$SRC_REPO") &>/dev/null
  else
    echo "docker-registry-ui 镜像无需更新"
  fi
else
  echo "获取Images ID失败请稍后再试！"
fi
EOF

    chmod +x /opt/script/syncimage/SyncImage.sh

    WARN "* 表示 每 的意思,例如 0 0 * * * 表示每天的凌晨24点执行"
    read -e -p "$(echo -e ${GREEN}"请输入分钟（0-59）: "${RESET})" minute
    read -e -p "$(echo -e ${GREEN}"请输入小时（0-23）: "${RESET})" hour
    read -e -p "$(echo -e ${GREEN}"请输入日期（1-31）: "${RESET})" day
    read -e -p "$(echo -e ${GREEN}"请输入月份（1-12）: "${RESET})" month
    read -e -p "$(echo -e ${GREEN}"请输入星期几（0-7，其中0和7都表示星期日）: "${RESET})" weekday
    INFO
    schedule="$minute $hour $day $month $weekday"
    # 提示用户的定时任务执行时间
    INFO "您的定时任务已设置为在 $schedule 时间内执行！"

    # 获取当前用户的crontab内容
    existing_crontab=$(crontab -l 2>/dev/null)

    # 要添加的定时任务
    new_cron="$schedule /opt/script/syncimage/SyncImage.sh"

    # 判断crontab中是否存在相同的定时任务
    if echo "$existing_crontab" | grep -qF "$new_cron"; then
        WARN "已存在相同的定时任务！"
    else
        # 添加定时任务到crontab
        (crontab -l ; echo "$new_cron") | crontab -
        INFO "已成功添加定时任务！"
    fi
elif [[ "$cron" == "n" ]]; then
    # 取消定时任务
    WARN "已取消定时更新镜像任务！"
else
    ERROR "选项错误！请重新运行脚本并选择正确的选项。"
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
  ADD_CRON
  PROMPT
}
main
