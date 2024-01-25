#!/usr/bin/env bash

# 定义路径和文件名
SCRIPT_PATH="/data/chatgpt-mirai-qq-bot/"
SCRIPT_NAME="bot.py"
LOG_FILE="qqbot.log"
CONFIG_FILE="config.cfg"

# 定义颜色
GREEN="\e[32m"
RED="\e[31m"
RESET="\e[0m"

# 菜单
echo "1. 启动服务"
echo "2. 更新Token"
echo "3. 退出"

# 读取用户输入
read -e -p "$(echo -e ${GREEN}"请选择操作 [1-3]: "${RESET})" choice

case $choice in
  1)
    # 启动服务
    existing_pid=$(pgrep -f "$SCRIPT_NAME")
    if [ -n "$existing_pid" ]; then
      read -e -p "$(echo -e ${GREEN}"已存在运行中的进程 (PID: $existing_pid)。是否强制重启？(y/n): "${RESET})" force_restart
      if [ "$force_restart" == "y" ]; then
        echo "强制重启中..."
        kill -9 "$existing_pid"
        sleep 2
      else
        echo "已取消启动新进程。"
        exit 0
      fi
    fi

    cd "$SCRIPT_PATH" || exit
    nohup python3 "$SCRIPT_NAME" > "$LOG_FILE" 2>&1 &
    echo "新进程已启动。"
    ;;
  2)
    # 更新Token
    read -e -p "$(echo -e ${GREEN}"请输入新的Token: "${RESET})" new_token
    file_path="$SCRIPT_PATH$CONFIG_FILE"
    sed -i "s/\(access_token = \).*/\1\"$new_token\"/" "$file_path"
    echo -e "${GREEN}Token已更新。${RESET}"

    # 重启程序
    existing_pid=$(pgrep -f "$SCRIPT_NAME")
    if [ -n "$existing_pid" ]; then
      echo -e "${GREEN}正在重启程序...${RESET}"
      kill -9 "$existing_pid"
      sleep 2
      cd "$SCRIPT_PATH" || exit
      nohup python3 "$SCRIPT_NAME" > "$LOG_FILE" 2>&1 &
      echo -e "${GREEN}程序已重启。${RESET}"
    else
      # 如果程序未启动，则启动程序
      cd "$SCRIPT_PATH" || exit
      nohup python3 "$SCRIPT_NAME" > "$LOG_FILE" 2>&1 &
      echo -e "${GREEN}程序已启动。${RESET}"
    fi
    ;;
  3)
    # 退出
    echo -e "${GREEN}退出脚本。${RESET}"
    exit 0
    ;;
  *)
    echo -e "${RED}无效的选择。${RESET}"
    exit 1
    ;;
esac
