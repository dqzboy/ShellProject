#!/usr/bin/env bash
# 使用代理
export proxy="http://127.0.0.1:7890"
export http_proxy=$proxy
export https_proxy=$proxy
export ftp_proxy=$proxy
export no_proxy="localhost, 127.0.0.1, ::1"
# WORKING_DIR：指定docker-compose.yml文件所在的目录
WORKING_DIR="/data/deepseek-free-api/"
cd "${WORKING_DIR}"
CONTAINER_NAME="deepseek-free-api"
IMAGE_NAME="vinlic/deepseek-free-api"
DOCKER_COMPOSE_FILE="docker-compose.yml"
stop_and_remove_container() {
    # 检查容器是否存在并停止并移除
    if docker ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then
        docker compose down
	docker compose down --remove-orphans
    fi
}
remove_none_tags() {
    # 删除标记为<none>的${IMAGE_NAME}镜像
    docker images | grep "^${IMAGE_NAME}.*<none>" | awk '{print $3}' | xargs -r docker rmi
    # 获取 deanxv/coze-discord-proxy 镜像列表，以仓库名和标签的格式显示
    images=$(docker images ${IMAGE_NAME} --format '{{.Repository}}:{{.Tag}}')
    # 获取最新的镜像版本
    latest=$(echo "$images" | sort -V | tail -n 1)
    # 遍历所有的镜像
    for image in $images
    do
      # 如果镜像不是最新的版本，就删除它
      if [ "$image" != "$latest" ];then
        docker rmi $image
      fi
    done
}

update_image_version() {
    # 提示用户输入新的版本号，并更新docker-compose文件
    read -e -p "请输入更新的版本号并按 Enter 键(eg: v3.2.3), 直接回车默认为latest: " version_number
    if [[ -z "$version_number" ]]; then
        version_number="latest"
    fi
    sed -i "s|${IMAGE_NAME}:.*|${IMAGE_NAME}:$version_number|" $DOCKER_COMPOSE_FILE
}

echo "请选择操作:"
echo "1) 重启"
echo "2) 更新"
echo "3) 新装"
echo "4) 卸载"
read -e -p "输入对应数字并按 Enter 键: " user_choice
case $user_choice in
    1)
        echo "--------------------重启中--------------------"
	docker stop ${CONTAINER_NAME}
        docker compose restart
        echo "-------------------- DONE --------------------"
        ;;
    2)
        echo "--------------------更新中--------------------"
        update_image_version
        docker compose pull
        docker compose up -d --force-recreate
        remove_none_tags
        echo "-------------------- DONE --------------------"
        ;;
    3)
        echo "--------------------新装中--------------------"
        stop_and_remove_container
        docker compose up -d
        echo "-------------------- DONE --------------------"
        ;;
    4)
        echo "--------------------卸载中--------------------"
        stop_and_remove_container
        remove_none_tags
	docker rmi $(docker images -q ${IMAGE_NAME}) &>/dev/null
        echo "-------------------- DONE --------------------"
        ;;
    *)
        echo "输入了无效的选择。请重新运行脚本并选择1-4的选项。"
        ;;
esac
