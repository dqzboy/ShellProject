#!/bin/bash

# 定义颜色和格式
GREEN="\033[0;32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"
BLUE="\033[0;34m"
MAGENTA="\033[0;35m"
CYAN="\033[0;36m"
WHITE="\033[1;37m"
BLACK="\033[0;30m"
LIGHT_GREEN="\033[1;32m"
LIGHT_RED="\033[1;31m"
LIGHT_YELLOW="\033[1;33m"
LIGHT_BLUE="\033[1;34m"
LIGHT_MAGENTA="\033[1;35m"
LIGHT_CYAN="\033[1;36m"
BOLD="\033[1m"
UNDERLINE="\033[4m"
BLINK="\033[5m"
REVERSE="\033[7m"

# 定义消息类型
INFO="[${GREEN}INFO${RESET}]"
ERROR="[${RED}ERROR${RESET}]"
WARN="[${YELLOW}WARN${RESET}]"
DEBUG="[${BLUE}DEBUG${RESET}]"
SUCCESS="[${CYAN}SUCCESS${RESET}]"
CRITICAL="[${LIGHT_RED}${BOLD}CRITICAL${RESET}]"
NOTICE="[${LIGHT_GREEN}NOTICE${RESET}]"
ALERT="[${MAGENTA}ALERT${RESET}]"
EMERGENCY="[${RED}${BLINK}EMERGENCY${RESET}]"

# 定义函数
function INFO() {
    echo -e "${INFO} ${1}"
}

function ERROR() {
    echo -e "${ERROR} ${1}"
}

function WARN() {
    echo -e "${WARN} ${1}"
}

function DEBUG() {
    echo -e "${DEBUG} ${1}"
}

function SUCCESS() {
    echo -e "${SUCCESS} ${1}"
}

function CRITICAL() {
    echo -e "${CRITICAL} ${1}"
}

function NOTICE() {
    echo -e "${NOTICE} ${1}"
}

function ALERT() {
    echo -e "${ALERT} ${1}"
}

function EMERGENCY() {
    echo -e "${EMERGENCY} ${1}"
}

# 打印提示信息
INFO "${BOLD}${RED}错误:${RESET} ${YELLOW}TLS握手超时${RESET} ${BLUE}(请检查网络连接)${RESET}"
WARN "${BOLD}${GREEN}提示:${RESET} ${CYAN}尝试重启网络设备${RESET} ${MAGENTA}(可能解决问题)${RESET}"
ERROR "${BOLD}${MAGENTA}注意:${RESET} ${UNDERLINE}确保Docker版本兼容${RESET}"
DEBUG "${BOLD}${MAGENTA}调试:${RESET} ${UNDERLINE}正在检查网络配置${RESET}"
SUCCESS "${BOLD}${GREEN}成功:${RESET} ${CYAN}网络连接已恢复${RESET}"
CRITICAL "${BOLD}${LIGHT_RED}严重:${RESET} ${LIGHT_YELLOW}系统资源不足${RESET} ${LIGHT_BLUE}(请立即采取措施)${RESET}"
NOTICE "${BOLD}${LIGHT_GREEN}通知:${RESET} ${LIGHT_CYAN}即将进行系统维护${RESET} ${LIGHT_MAGENTA}(请提前保存工作)${RESET}"
ALERT "${BOLD}${MAGENTA}警报:${RESET} ${WHITE}检测到可疑活动${RESET} ${BLACK}(请检查日志)${RESET}"
EMERGENCY "${BOLD}${RED}${BLINK}紧急:${RESET} ${LIGHT_RED}系统崩溃${RESET} ${LIGHT_YELLOW}(请联系技术支持)${RESET}"
