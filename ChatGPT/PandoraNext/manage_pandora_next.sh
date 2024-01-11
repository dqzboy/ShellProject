#!/usr/bin/env bash
#===============================================================================
#
#          FILE: manage_pandora_next.sh
#
#         USAGE: ./manage_pandora_next.sh
#
#   DESCRIPTION: 管理 PandoraNext 容器
#
#  ORGANIZATION: DingQz dqzboy.com
#===============================================================================

# 指定 pandora-next 项目的 docker-compose.yml 文件的路径
PANDORA_NEXT_PATH="/data/pandora-next/deploy"

cd "${PANDORA_NEXT_PATH}"

CONTAINER_NAME="PandoraNext"
IMAGE_NAME="pengzhile/pandora-next"

echo "请选择操作:"
echo "1) 重启"
echo "2) 更新"
echo "3) 新装"
echo "4) 卸载"

read -p "输入对应数字并按 Enter 键: " user_choice

case $user_choice in
    1) # 重启
        docker restart "${CONTAINER_NAME}"
        ;;
    2) # 更新
        docker-compose down
        docker-compose pull
        docker-compose up -d
        ;;
    3) # 新装
        # 检查容器是否存在
        if docker ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then
            docker-compose down
        fi
        # 拉取新镜像
        docker pull "${IMAGE_NAME}"
        # 创建并运行容器
        docker-compose up -d
        ;;
    4) # 卸载
        # 检查容器是否存在
        if docker ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then
            docker-compose down
        fi
        # 删除镜像
        docker rmi "${IMAGE_NAME}"
        ;;
    *)
        echo "无效的选择"
        ;;
esac
