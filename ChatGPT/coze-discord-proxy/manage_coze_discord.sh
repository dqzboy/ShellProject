#!/usr/bin/env bash
cd /data/coze-discord-proxy
CONTAINER_NAME="coze-discord-proxy"
IMAGE_NAME="deanxv/coze-discord-proxy"
stop_and_remove_container() {
    # 检查容器是否存在并停止移除
    if docker ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then
        docker-compose down
    fi
}
pull_image() {
    docker pull "${IMAGE_NAME}"
}

echo "请选择操作:"
echo "1) 重启"
echo "2) 更新"
echo "3) 新装"
echo "4) 卸载"

read -e -p "输入对应数字并按 Enter 键: " user_choice

case $user_choice in
    1)
        echo "重启中..."
        docker-compose restart
        ;;
    2)
        echo "更新中..."
        stop_and_remove_container
        pull_image
        docker-compose up -d
        ;;
    3)
        echo "新装中..."
        stop_and_remove_container
        pull_image
        docker-compose up -d
        ;;
    4)
        echo "卸载中..."
        stop_and_remove_container
        docker rmi "${IMAGE_NAME}"
        ;;
    *)
        echo "输入了无效的选择。请重新运行脚本并选择1-4的选项。"
        ;;
esac
