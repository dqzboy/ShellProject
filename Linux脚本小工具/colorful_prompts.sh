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
# 打印提示信息
INFO "${BOLD}${RED}错误:${RESET} ${YELLOW}这是黄色，变量为YELLOW${RESET} ${BLUE}这是蓝色，变量为BLUE${RESET}"  # 打印颜色: 绿色
WARN "${BOLD}${GREEN}提示:${RESET} ${CYAN}这是青色，变量为CYAN${RESET} ${MAGENTA}这是紫色，变量为MAGENTA${RESET}"  # 打印颜色: 黄色
ERROR "${BOLD}${MAGENTA}注意:${RESET} ${UNDERLINE}这是下划线，变量为UNDERLINE${RESET}"  # 打印颜色: 红色
DEBUG "${BOLD}${MAGENTA}调试:${RESET} ${UNDERLINE}这是下划线，变量为UNDERLINE${RESET}"  # 打印颜色: 蓝色
SUCCESS "${BOLD}${GREEN}成功:${RESET} ${CYAN}这是青色，变量为CYAN${RESET}"  # 打印颜色: 青色
CRITICAL "${BOLD}${LIGHT_RED}严重:${RESET} ${LIGHT_YELLOW}这是浅黄色，变量为LIGHT_YELLOW${RESET} ${LIGHT_BLUE}这是浅蓝色，变量为LIGHT_BLUE${RESET}"  # 打印颜色: 浅红色
NOTICE "${BOLD}${LIGHT_GREEN}通知:${RESET} ${LIGHT_CYAN}这是浅青色，变量为LIGHT_CYAN${RESET} ${LIGHT_MAGENTA}这是浅紫色，变量为LIGHT_MAGENTA${RESET}"  # 打印颜色: 浅绿色
ALERT "${BOLD}${MAGENTA}警报:${RESET} ${WHITE}这是白色，变量为WHITE${RESET} ${BLACK}这是黑色，变量为BLACK${RESET}"  # 打印颜色: 紫色
EMERGENCY "${BOLD}${RED}${BLINK}紧急:${RESET} ${LIGHT_RED}这是浅红色，变量为LIGHT_RED${RESET} ${LIGHT_YELLOW}这是浅黄色，变量为LIGHT_YELLOW${RESET}"  # 打印颜色: 红色（闪烁）
