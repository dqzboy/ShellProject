#!/bin/bash

# 定义颜色和格式
GREEN="\033[0;32m"          # 绿色
RED="\033[31m"             # 红色
YELLOW="\033[33m"          # 黄色
RESET="\033[0m"            # 重置颜色
BLUE="\033[0;34m"          # 蓝色
MAGENTA="\033[0;35m"       # 洋红
CYAN="\033[0;36m"          # 青色
WHITE="\033[1;37m"         # 白色
BLACK="\033[0;30m"         # 黑色
LIGHT_GREEN="\033[1;32m"   # 浅绿色
LIGHT_RED="\033[1;31m"     # 浅红色
LIGHT_YELLOW="\033[1;33m"  # 浅黄色
LIGHT_BLUE="\033[1;34m"    # 浅蓝色
LIGHT_MAGENTA="\033[1;35m" # 浅洋红
LIGHT_CYAN="\033[1;36m"    # 浅青色
BOLD="\033[1m"             # 加粗
UNDERLINE="\033[4m"        # 下划线
BLINK="\033[5m"            # 闪烁
REVERSE="\033[7m"          # 反转

# Additional colors
DARK_GRAY="\033[1;30m"     # 深灰色
LIGHT_GRAY="\033[0;37m"    # 浅灰色
ORANGE="\033[0;91m"        # 橙色
LIGHT_ORANGE="\033[1;91m"  # 浅橙色
PINK="\033[0;95m"          # 粉色
LIGHT_PINK="\033[1;95m"    # 浅粉色
BRIGHT_RED="\033[91m"      # 亮红色
BRIGHT_GREEN="\033[92m"    # 亮绿色
BRIGHT_YELLOW="\033[93m"   # 亮黄色
BRIGHT_BLUE="\033[94m"     # 亮蓝色
BRIGHT_MAGENTA="\033[95m"  # 亮洋红
BRIGHT_CYAN="\033[96m"     # 亮青色
BRIGHT_WHITE="\033[97m"    # 亮白色
DIM="\033[2m"              # 暗色
ITALIC="\033[3m"           # 斜体

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

# 定义列表输出函数
function LIST_ITEM() {
    local ITEM="${1}"
    echo -e "${BOLD}${CYAN}- ${RESET}${ITEM}"
}

# 定义表格输出函数
function TABLE_ROW() {
    local ROW="${1}"
    echo -e "${BOLD}${WHITE}| ${RESET}${ROW} ${BOLD}${WHITE}|${RESET}"
}

function TABLE_HEADER() {
    local HEADER="${1}"
    echo -e "${BOLD}${BLUE}| ${RESET}${HEADER} ${BOLD}${BLUE}|${RESET}"
    echo -e "${BOLD}${BLUE}---------------------------------${RESET}"
}

# 定义带颜色的日志记录函数
LOG_FILE="script.log"
function LOG_INFO() {
    echo -e "${INFO} ${1}" | tee -a ${LOG_FILE}
}

function LOG_ERROR() {
    echo -e "${ERROR} ${1}" | tee -a ${LOG_FILE}
}

function LOG_WARN() {
    echo -e "${WARN} ${1}" | tee -a ${LOG_FILE}
}

# 定义标题输出函数
function TITLE() {
    local TITLE="${1}"
    echo -e "${BOLD}${UNDERLINE}${MAGENTA}${TITLE}${RESET}"
}

# 定义分割线函数
function SEPARATOR() {
    echo -e "${INFO}${BOLD}${LIGHT_BLUE}========================${1}========================${RESET}"
}


echo -e "${GREEN}GREEN: 绿色${RESET}"
echo -e "${RED}RED: 红色${RESET}"
echo -e "${YELLOW}YELLOW: 黄色${RESET}"
echo -e "${BLUE}BLUE: 蓝色${RESET}"
echo -e "${MAGENTA}MAGENTA: 洋红${RESET}"
echo -e "${CYAN}CYAN: 青色${RESET}"
echo -e "${WHITE}WHITE: 白色${RESET}"
echo -e "${BLACK}BLACK: 黑色${RESET}"
echo -e "${LIGHT_GREEN}LIGHT_GREEN: 浅绿色${RESET}"
echo -e "${LIGHT_RED}LIGHT_RED: 浅红色${RESET}"
echo -e "${LIGHT_YELLOW}LIGHT_YELLOW: 浅黄色${RESET}"
echo -e "${LIGHT_BLUE}LIGHT_BLUE: 浅蓝色${RESET}"
echo -e "${LIGHT_MAGENTA}LIGHT_MAGENTA: 浅洋红${RESET}"
echo -e "${LIGHT_CYAN}LIGHT_CYAN: 浅青色${RESET}"
echo -e "${BOLD}BOLD: 加粗${RESET}"
echo -e "${UNDERLINE}UNDERLINE: 下划线${RESET}"
echo -e "${BLINK}BLINK: 闪烁${RESET}"
echo -e "${REVERSE}REVERSE: 反转${RESET}"
echo -e "${DARK_GRAY}DARK_GRAY: 深灰色${RESET}"
echo -e "${LIGHT_GRAY}LIGHT_GRAY: 浅灰色${RESET}"
echo -e "${ORANGE}ORANGE: 橙色${RESET}"
echo -e "${LIGHT_ORANGE}LIGHT_ORANGE: 浅橙色${RESET}"
echo -e "${PINK}PINK: 粉色${RESET}"
echo -e "${LIGHT_PINK}LIGHT_PINK: 浅粉色${RESET}"
echo -e "${BRIGHT_RED}BRIGHT_RED: 亮红色${RESET}"
echo -e "${BRIGHT_GREEN}BRIGHT_GREEN: 亮绿色${RESET}"
echo -e "${BRIGHT_YELLOW}BRIGHT_YELLOW: 亮黄色${RESET}"
echo -e "${BRIGHT_BLUE}BRIGHT_BLUE: 亮蓝色${RESET}"
echo -e "${BRIGHT_MAGENTA}BRIGHT_MAGENTA: 亮洋红${RESET}"
echo -e "${BRIGHT_CYAN}BRIGHT_CYAN: 亮青色${RESET}"
echo -e "${BRIGHT_WHITE}BRIGHT_WHITE: 亮白色${RESET}"
echo -e "${DIM}DIM: 暗色${RESET}"
echo -e "${ITALIC}ITALIC: 斜体${RESET}"

# 示例：打印提示信息
SEPARATOR "开始"
TITLE "信息输出示例"
SEPARATOR "颜色"
INFO "${BOLD}${RED}错误:${RESET} ${YELLOW}这是黄色，变量为YELLOW${RESET} ${BLUE}这是蓝色，变量为BLUE${RESET}"  # 打印颜色: 绿色
WARN "${BOLD}${GREEN}提示:${RESET} ${CYAN}这是青色，变量为CYAN${RESET} ${MAGENTA}这是紫色，变量为MAGENTA${RESET}"  # 打印颜色: 黄色
ERROR "${BOLD}${MAGENTA}注意:${RESET} ${UNDERLINE}这是下划线，变量为UNDERLINE${RESET}"  # 打印颜色: 红色
DEBUG "${BOLD}${MAGENTA}调试:${RESET} ${UNDERLINE}这是下划线，变量为UNDERLINE${RESET}"  # 打印颜色: 蓝色
SUCCESS "${BOLD}${GREEN}成功:${RESET} ${CYAN}这是青色，变量为CYAN${RESET}"  # 打印颜色: 青色
CRITICAL "${BOLD}${LIGHT_RED}严重:${RESET} ${LIGHT_YELLOW}这是浅黄色，变量为LIGHT_YELLOW${RESET} ${LIGHT_BLUE}这是浅蓝色，变量为LIGHT_BLUE${RESET}"  # 打印颜色: 浅红色
NOTICE "${BOLD}${LIGHT_GREEN}通知:${RESET} ${LIGHT_CYAN}这是浅青色，变量为LIGHT_CYAN${RESET} ${LIGHT_MAGENTA}这是浅紫色，变量为LIGHT_MAGENTA${RESET}"  # 打印颜色: 浅绿色
ALERT "${BOLD}${MAGENTA}警报:${RESET} ${WHITE}这是白色，变量为WHITE${RESET} ${BLACK}这是黑色，变量为BLACK${RESET}"  # 打印颜色: 紫色
EMERGENCY "${BOLD}${RED}${BLINK}紧急:${RESET} ${LIGHT_RED}这是浅红色，变量为LIGHT_RED${RESET} ${LIGHT_YELLOW}这是浅黄色，变量为LIGHT_YELLOW${RESET}"  # 打印颜色: 红色（闪烁）

SEPARATOR "列表"
# 示例：打印一个列表
TITLE "示例列表"
LIST_ITEM "项1: 示例内容"
LIST_ITEM "项2: 更多示例内容"
LIST_ITEM "项3: 其他内容"

SEPARATOR "表格"
# 示例：打印一个表格
TITLE "示例表格"
TABLE_HEADER "列1  | 列2   | 列3  "
TABLE_ROW "数据1 | 数据2 | 数据3"
TABLE_ROW "数据4 | 数据5 | 数据6"
TABLE_ROW "数据7 | 数据8 | 数据9"

SEPARATOR "日志"
# 示例：日志记录
TITLE "日志记录示例"
LOG_INFO "这是一个信息日志"
LOG_WARN "这是一个警告日志"
LOG_ERROR "这是一个错误日志"
SEPARATOR "结束"
