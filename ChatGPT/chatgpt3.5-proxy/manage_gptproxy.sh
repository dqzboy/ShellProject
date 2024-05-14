#!/usr/bin/env bash

#定义容器名称和镜像名称
CONTAINER_NAME="chatgpt"
IMAGE_NAME="pawanosman/chatgpt"
PORT="3040"

#检查Docker是否安装
if ! command -v docker &> /dev/null
then
    echo "Docker未安装。请先安装Docker。"
    exit1
fi

#函数：启动容器
start_container() {
    if docker inspect -f '{{.State.Running}}' ${CONTAINER_NAME} &> /dev/null; then
        echo "容器 ${CONTAINER_NAME}已经在运行中。"
    else
        echo "正在启动容器..."
        docker run -d -p ${PORT}:${PORT} --name ${CONTAINER_NAME} ${IMAGE_NAME}:latest
    fi
}

#函数：重启容器
restart_container() {
    echo "正在重启容器..."
    docker restart ${CONTAINER_NAME}
}

#函数：更新容器
update_container() {
    echo "正在更新容器..."
    #停止并删除现有容器
    docker stop ${CONTAINER_NAME}
    docker rm ${CONTAINER_NAME}
    #删除旧的镜像
    docker rmi -f ${IMAGE_NAME}:latest
    # 删除标记为<none>的${IMAGE_NAME}镜像
    docker images | grep "^${IMAGE_NAME}.*<none>" | awk '{print $3}' | xargs -r docker rmi
    #拉取最新镜像并启动新容器
    start_container
}

#函数：卸载容器
uninstall_container() {
    echo "正在卸载容器..."
    #停止并删除容器
    docker stop ${CONTAINER_NAME}
    docker rm ${CONTAINER_NAME}
    #删除镜像
    docker rmi -f ${IMAGE_NAME}:latest
    # 删除标记为<none>的${IMAGE_NAME}镜像
    docker images | grep "^${IMAGE_NAME}.*<none>" | awk '{print $3}' | xargs -r docker rmi
}

#函数：打印容器日志
print_logs() {
    if docker inspect -f '{{.State.Running}}' ${CONTAINER_NAME} &> /dev/null; then
        echo "正在打印容器日志..."
        docker logs ${CONTAINER_NAME}
    else
        echo "容器未启动。请先启动容器。"
    fi
}

#主菜单循环
while true; do
    echo "容器管理菜单："
    echo "1.启动容器"
    echo "2.重启容器"
    echo "3.更新容器"
    echo "4.卸载容器"
    echo "5.打印容器日志"
    echo "6.退出"

    read -p "请输入您的选择： " choice

    case $choice in
        1)
            start_container
            ;;
        2)
            restart_container
            ;;
        3)
            update_container
            ;;
        4)
            uninstall_container
            ;;
        5)
            print_logs
            ;;
        6)
            echo "正在退出..."
            break
            ;;
        *)
            echo "无效的选择。请重新尝试。"
            ;;
    esac
done
