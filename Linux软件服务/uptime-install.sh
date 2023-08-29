#!/bin/bash

# 询问用户是新装还是升级
read -e -p "您是要新装还是升级？(输入 '新装' 或 '升级')：" INSTALL_TYPE

if [ "${INSTALL_TYPE}" == "升级" ]; then
    # 检查容器是否在运行
    if docker ps -a --format '{{.Names}}' | grep -q "uptime-kuma"; then
        # 停止旧版本容器
        docker stop uptime-kuma
        echo "已停止旧版本容器。"
    fi

    # 删除旧版本镜像
    docker image rm louislam/uptime-kuma:1
    echo "已删除旧版本镜像。"

    # 下载最新版本镜像
    docker pull louislam/uptime-kuma:1
    echo "已下载最新版本镜像。"
else
    MAX_TRIES=3

    for ((try=1; try<=${MAX_TRIES}; try++)); do
        read -e -p "请输入监听的端口：" PORT

        # 检查端口是否已被占用
        if ss -tulwn | grep -q ":${PORT} "; then
            echo "端口 ${PORT} 已被占用，请尝试其他端口。"
            if [ "${try}" -lt "${MAX_TRIES}" ]; then
                echo "您还有 $((${MAX_TRIES} - ${try})) 次尝试机会。"
            else
                echo "您已用尽所有尝试机会。"
                exit 1
            fi
        else
            break
        fi
    done

    # 提示用户输入映射的目录
    read -e -p "请输入映射的目录：" MAPPING_DIR

    # 检查目录是否存在，如果不存在则创建
    if [ ! -d "${MAPPING_DIR}" ]; then
        mkdir -p "${MAPPING_DIR}"
        echo "目录已创建：${MAPPING_DIR}"
    fi

    # 启动 Docker 容器
    docker run -d --restart=always -p "${PORT}":3001 -v "${MAPPING_DIR}":/app/data --name uptime-kuma louislam/uptime-kuma:latest
    echo "已启动 Uptime Kuma 容器，监听端口 ${PORT}。"
fi

# 如果是升级则启动容器
if [ "${INSTALL_TYPE}" == "升级" ]; then
    docker start uptime-kuma
    echo "已启动 Uptime Kuma 容器。"
fi

echo "已成功${INSTALL_TYPE}并完成操作。"
