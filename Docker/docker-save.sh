#!/bin/bash

# 提示用户输入镜像名称和tag
read -e -p "请输入镜像名称: " IMAGE_NAME
read -e -p "请输入镜像tag (默认为latest): " IMAGE_TAG

# 如果用户没有输入tag,则默认使用latest
if [ -z "$IMAGE_TAG" ]; then
    IMAGE_TAG="latest"
fi

# 完整的镜像名称
FULL_IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"

echo "正在从Docker Hub下载镜像: $FULL_IMAGE_NAME"

# 从Docker Hub下载镜像
docker pull $FULL_IMAGE_NAME

# 检查下载是否成功
if [ $? -ne 0 ]; then
    echo "镜像下载失败,请检查镜像名称和网络连接"
    exit 1
fi

echo "镜像下载成功"

# 生成打包文件名
ARCHIVE_NAME="${IMAGE_NAME}_${IMAGE_TAG}.tar"

echo "正在将镜像保存为: $ARCHIVE_NAME"

# 将镜像保存为tar文件
docker save -o $ARCHIVE_NAME $FULL_IMAGE_NAME

# 检查保存是否成功
if [ $? -ne 0 ]; then
    echo "镜像保存失败"
    exit 1
fi

echo "镜像已成功保存为: $ARCHIVE_NAME"
