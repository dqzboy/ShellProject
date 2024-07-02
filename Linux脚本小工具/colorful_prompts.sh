#!/bin/bash

# 定义颜色和格式
GREEN="\033[0;32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"
BLUE="\033[0;34m"
MAGENTA="\033[0;35m"
CYAN="\033[0;36m"
BOLD="\033[1m"
UNDERLINE="\033[4m"

# 定义消息类型
INFO="[${GREEN}INFO${RESET}]"
ERROR="[${RED}ERROR${RESET}]"
WARN="[${YELLOW}WARN${RESET}]"
DEBUG="[${BLUE}DEBUG${RESET}]"
SUCCESS="[${CYAN}SUCCESS${RESET}]"

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

# 打印提示信息
INFO "${BOLD}${RED}错误:${RESET} ${YELLOW}TLS握手超时${RESET} ${BLUE}(请检查网络连接)${RESET}"
WARN "${BOLD}${GREEN}提示:${RESET} ${CYAN}尝试重启网络设备${RESET} ${MAGENTA}(可能解决问题)${RESET}"
ERROR "${BOLD}${MAGENTA}注意:${RESET} ${UNDERLINE}确保Docker版本兼容${RESET}"
DEBUG "${BOLD}${MAGENTA}调试:${RESET} ${UNDERLINE}正在检查网络配置${RESET}"
SUCCESS "${BOLD}${GREEN}成功:${RESET} ${CYAN}网络连接已恢复${RESET}"
