#!/usr/bin/env bash
#===============================================================================
#
#          FILE: build_new_img.sh
# 
#         USAGE: ./build_new_img.sh
#
#  ORGANIZATION: DingQz dqzboy.com 浅时光博客
#===============================================================================

echo
cat << EOF

    ██████╗  ██████╗  ██████╗██╗  ██╗███████╗██████╗     ██████╗ ██████╗  ██████╗ ██╗  ██╗██╗   ██╗
    ██╔══██╗██╔═══██╗██╔════╝██║ ██╔╝██╔════╝██╔══██╗    ██╔══██╗██╔══██╗██╔═══██╗╚██╗██╔╝╚██╗ ██╔╝
    ██║  ██║██║   ██║██║     █████╔╝ █████╗  ██████╔╝    ██████╔╝██████╔╝██║   ██║ ╚███╔╝  ╚████╔╝ 
    ██║  ██║██║   ██║██║     ██╔═██╗ ██╔══╝  ██╔══██╗    ██╔═══╝ ██╔══██╗██║   ██║ ██╔██╗   ╚██╔╝  
    ██████╔╝╚██████╔╝╚██████╗██║  ██╗███████╗██║  ██║    ██║     ██║  ██║╚██████╔╝██╔╝ ██╗   ██║   
    ╚═════╝  ╚═════╝  ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝    ╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   
                                                                                               
EOF

echo "----------------------------------------------------------------------------------------------------------"
echo -e "\033[32m机场推荐\033[0m(\033[34m按量不限时，解锁ChatGPT\033[0m)：\033[34;4mhttps://mojie.mx/#/register?code=CG6h8Irm\033[0m"
echo "----------------------------------------------------------------------------------------------------------"
echo
echo

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


LOCAL_IMAGE_NAME="dqzboy"
LOCAL_IMAGE_TAG="latest"
REMOTE_IMAGE_NAME="dqzboy/dqzboy"

function BUILD_IMG() {
    INFO "=======================构建新版镜像 ======================="
    if [ -f "Dockerfile" ]; then
        docker build -t ${LOCAL_IMAGE_NAME}:${LOCAL_IMAGE_TAG} .
    else
        ERROR "Dockerfile not found in the current directory."
        exit1
    fi
}

function PUSH_IMG() {
    INFO "=======================上传最新镜像 ======================="
    docker tag ${LOCAL_IMAGE_NAME}:${LOCAL_IMAGE_TAG} ${REMOTE_IMAGE_NAME}:${LOCAL_IMAGE_TAG}
    docker push ${REMOTE_IMAGE_NAME}:${LOCAL_IMAGE_TAG}
}

function DELETE_IMG() {
    INFO "=======================删除本地镜像 ======================="
    docker rmi ${LOCAL_IMAGE_NAME}:${LOCAL_IMAGE_TAG}
    docker rmi ${REMOTE_IMAGE_NAME}:${LOCAL_IMAGE_TAG}
}

main(){
BUILD_IMG
PUSH_IMG
DELETE_IMG
}
main
