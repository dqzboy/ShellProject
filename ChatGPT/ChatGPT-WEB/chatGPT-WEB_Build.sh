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
if [ -f /etc/redhat-release ]; then
    echo "This is CentOS."
    source ${PWD}/chatGPT-WEB_C.sh
elif [ -f /etc/lsb-release ]; then
    if grep -q "DISTRIB_ID=Ubuntu" /etc/lsb-release; then
        echo "This is Ubuntu."
	source ${PWD}/chatGPT-WEB_U.sh
    else
        echo "Unknown Linux distribution."
	exit 1
    fi
else
    echo "Unknown Linux distribution."
    exit 2
fi
