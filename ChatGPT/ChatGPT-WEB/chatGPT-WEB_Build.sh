#!/usr/bin/env bash
#===============================================================================
#
#          FILE: chatGPT-WEB_Build.sh
#
#         USAGE: ./chatGPT-WEB_Build.sh
#
#   DESCRIPTION: chatGPT-WEB项目一键构建、部署脚本;支持CentOS与Ubuntu
#
#  ORGANIZATION: DingQz dqzboy.com
#===============================================================================

SETCOLOR_SKYBLUE="echo -en \\E[1;36m"
SETCOLOR_SUCCESS="echo -en \\E[0;32m"
SETCOLOR_NORMAL="echo  -en \\E[0;39m"
SETCOLOR_RED="echo  -en \\E[0;31m"

function SUCCESS_ON() {
${SETCOLOR_SUCCESS} && echo "-------------------------------------<提 示>-------------------------------------" && ${SETCOLOR_NORMAL}
}

function SUCCESS_END() {
${SETCOLOR_SUCCESS} && echo "-------------------------------------< END >-------------------------------------" && ${SETCOLOR_NORMAL}
echo
}

function DL() {
${SETCOLOR_SUCCESS} && echo "------------------------------------<脚本下载>-------------------------------------" && ${SETCOLOR_NORMAL}
${SETCOLOR_RED} && echo "                           注: 国内服务器请选择参数 2 "
SUCCESS_END
${SETCOLOR_NORMAL}

read -e -p "请选择你的服务器网络环境[国外1/国内2]： " NETWORK
if [ ${NETWORK} == 1 ];then
    if [ -f /etc/redhat-release ]; then
        echo "This is CentOS."
        yum install nscd -y &>/dev/null
        systemctl restart nscd.service
        curl -sO -H 'Cache-Control: no-cache' https://raw.githubusercontent.com/dqzboy/ShellProject/main/ChatGPT/ChatGPT-WEB/chatGPT-WEB_C.sh 
        source ${PWD}/chatGPT-WEB_C.sh
    elif [ -f /etc/lsb-release ]; then
        if grep -q "DISTRIB_ID=Ubuntu" /etc/lsb-release; then
            echo "This is Ubuntu."
            systemctl restart systemd-resolved
            curl -sO -H 'Cache-Control: no-cache' https://raw.githubusercontent.com/dqzboy/ShellProject/main/ChatGPT/ChatGPT-WEB/chatGPT-WEB_U.sh
            source ${PWD}/chatGPT-WEB_U.sh
        else
            echo "Unknown Linux distribution."
            exit 1
        fi
    else
        echo "Unknown Linux distribution."
        exit 2
    fi
elif [ ${NETWORK} == 2 ];then
        if [ -f /etc/redhat-release ]; then
        echo "This is CentOS."
        yum install nscd -y &>/dev/null
        systemctl restart nscd.service
        curl -sO -H 'Cache-Control: no-cache' https://ghproxy.com/https://raw.githubusercontent.com/dqzboy/ShellProject/main/ChatGPT/ChatGPT-WEB/chatGPT-WEB_C.sh
        source ${PWD}/chatGPT-WEB_C.sh
    elif [ -f /etc/lsb-release ]; then
        if grep -q "DISTRIB_ID=Ubuntu" /etc/lsb-release; then
            echo "This is Ubuntu."
            systemctl restart systemd-resolved
            curl -sO -H 'Cache-Control: no-cache' https://ghproxy.com/https://raw.githubusercontent.com/dqzboy/ShellProject/main/ChatGPT/ChatGPT-WEB/chatGPT-WEB_U.sh
            source ${PWD}/chatGPT-WEB_U.sh
        else
            echo "Unknown Linux distribution."
            exit 1
        fi
    else
        echo "Unknown Linux distribution."
        exit 2
    fi
else
   echo "Parameter Error"
fi
SUCCESS_END
}

DL
