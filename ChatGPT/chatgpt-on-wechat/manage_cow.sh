#!/usr/bin/env bash

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# 指定app.py文件所在的目录
APP_DIR="/data/chatgpt-on-wechat"
APP_FILE="app.py"

# 获取Python应用程序的进程ID (PID)
get_pid() {
    echo $(ps aux | grep "[p]ython3 $APP_FILE" | awk '{print $2}')
}

# 函数：启动Python应用程序
start_app() {
    pid=$(get_pid)
    if [ ! -z "$pid" ]; then
        echo -e "${GREEN}应用程序已经在运行。 PID: $pid${NC}"
    else
        cd $APP_DIR
        if [ $? -eq 0 ]; then
            nohup python3 $APP_FILE > output.log 2>&1 &
            echo -e "${GREEN}应用程序已启动。${NC}"
        else
            echo -e "${RED}无法切换到应用程序目录: $APP_DIR ${NC}"
        fi
    fi
}

# 函数：停止Python应用程序
stop_app() {
    pid=$(get_pid)
    if [ ! -z "$pid" ]; then
        kill -9 $pid
        echo -e "${GREEN}应用程序已停止。${NC}"
    else
        echo -e "${RED}应用程序未在运行。${NC}"
    fi
}

# 函数：查看Python应用程序状态
check_status() {
    pid=$(get_pid)
    if [ ! -z "$pid" ]; then
        echo -e "${GREEN}应用程序正在运行。 PID: $pid${NC}"
    else
        echo -e "${RED}应用程序未在运行。${NC}"
    fi
}

# 重启Python应用程序
restart_app() {
    echo -e "${GREEN}正在重启应用程序...${NC}"
    stop_app
    sleep 2  # 等待两秒确保应用程序完全停止
    start_app
}

# 显示表格样式的菜单
function show_menu {
    echo -e "${GREEN}Python 应用管理菜单${NC}"
    echo "+-------------------+-----------------------+"
    echo "| 选项 | 描述                               |"
    echo "+-------------------+-----------------------+"
    echo "| 1    | 启动 Python 应用程序              |"
    echo "| 2    | 停止 Python 应用程序              |"
    echo "| 3    | 查看 Python 应用程序的运行状态    |"
    echo "| 4    | 重启 Python 应用程序              |"
    echo "| 5    | 退出                               |"
    echo "+-------------------+-----------------------+"
}

# 主菜单循环
while true; do
    show_menu
    read -e -p "$(echo -e ${GREEN}"请选择操作（1-5）: "${NC})" choice
    case "$choice" in
        1) start_app ;;
        2) stop_app ;;
        3) check_status ;;
        4) restart_app ;;
        5) exit ;;
        *) echo -e "${RED}无效选择，请输入1-5之间的数字。${NC}" ;;
    esac
done
