#!/usr/bin/env bash
# WORKING_DIR：指定docker-compose.yml文件所在的目录
WORKING_DIR="/data/coze-discord-proxy/"
cd "${WORKING_DIR}"
CONTAINER_NAME="coze-discord-proxy"
IMAGE_NAME="deanxv/coze-discord-proxy"
DOCKER_COMPOSE_FILE="docker-compose.yml"
stop_and_remove_container() {
    # 检查容器是否存在并停止并移除
    if docker ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then
        docker compose down
    fi
}
remove_none_tags() {
    # 删除标记为<none>的deanxv/coze-discord-proxy镜像
    docker images | grep "^${IMAGE_NAME}.*<none>" | awk '{print $3}' | xargs -r docker rmi
    # 删除所有未使用的deanxv/coze-discord-proxy镜像
    docker images --filter "dangling=true" --format '{{.Repository}}:{{.Tag}} {{.ID}}' | grep "^deanxv/coze-discord-proxy" | awk '{print $2}' | xargs -r docker rmi
}
update_image_version() {
    # 提示用户输入新的版本号，并更新docker-compose文件
    read -e -p "请输入更新的版本号并按 Enter 键(eg: v3.2.3): " version_number
    if [[ ! -z "$version_number" ]]; then
        sed -i "s|${IMAGE_NAME}:.*|${IMAGE_NAME}:$version_number|" $DOCKER_COMPOSE_FILE
    else
        echo "输入的版本号为空，未进行更新。"
    fi
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
	docker rmi $(docker images -q deanxv/coze-discord-proxy) &>/dev/null
        echo "-------------------- DONE --------------------"
        ;;
    *)
        echo "输入了无效的选择。请重新运行脚本并选择1-4的选项。"
        ;;
esac
