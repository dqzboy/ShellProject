#!/usr/bin/env bash
#===============================================================================
#
#          FILE: pandora-next-helper.sh
#
#         USAGE: ./pandora-next-helper.sh
#
#   DESCRIPTION: 部署pandora-next管理页面
#
#  ORGANIZATION: DingQz dqzboy.com
#===============================================================================

CONTAINER_NAME="PandoraNext-Helper"
IMAGE_NAME="q11391/pandora-next-helper"
DATA_VOLUME="<pandora-next项目中config.json所在的目录路径>"
PANDORA_NEXT_DOMAIN="http://<你的pandora-next地址>:8181"

echo "请选择操作:"
echo "1) 重启"
echo "2) 更新"
echo "3) 新装"
echo "4) 卸载"

read -p "输入对应数字并按 Enter 键: " user_choice

case $user_choice in
    1) # 重启
        docker restart ${CONTAINER_NAME}
        ;;
    2) # 更新
        docker stop ${CONTAINER_NAME}
        docker rm ${CONTAINER_NAME}
        docker pull ${IMAGE_NAME}
        docker run -d --restart=always --name ${CONTAINER_NAME} --net=bridge \
            -p 8182:8182 \
            -v ${DATA_VOLUME}:/data \
            -e PANDORA_NEXT_DOMAIN=${PANDORA_NEXT_DOMAIN} \
            ${IMAGE_NAME}
        ;;
    3) # 新装
        # 检查容器是否存在
        if docker ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then
            # 如果容器正在运行，停止它
            if docker ps -q -f name=${CONTAINER_NAME} | grep -q .; then
                docker stop ${CONTAINER_NAME}
            fi
            # 等待容器完全停止
            while docker ps -q -f name=${CONTAINER_NAME} | grep -q .; do
                sleep 1
            done
            # 删除容器
            docker rm ${CONTAINER_NAME}
        fi
        # 拉取新镜像
        docker pull ${IMAGE_NAME}
        # 创建并运行容器
        docker run -d --restart=always --name ${CONTAINER_NAME} --net=bridge \
            -p 8182:8182 \
            -v ${DATA_VOLUME}:/data \
            -e PANDORA_NEXT_DOMAIN=${PANDORA_NEXT_DOMAIN} \
            ${IMAGE_NAME}
        ;;
    4) # 卸载
        # 检查容器是否存在
        if docker ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then
            # 如果容器正在运行，停止它
            if docker ps -q -f name=${CONTAINER_NAME} | grep -q .; then
                docker stop ${CONTAINER_NAME}
            fi
            # 等待容器完全停止
            while docker ps -q -f name=${CONTAINER_NAME} | grep -q .; do
                sleep 1
            done
            # 删除容器
            docker rm ${CONTAINER_NAME}
        fi
        # 删除镜像
        docker rmi ${IMAGE_NAME}
        ;;
    *)
        echo "无效的选择"
        ;;
esac
