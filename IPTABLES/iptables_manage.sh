#!/usr/bin/env bash
#===============================================================================
#
#          FILE: iptables_manage.sh
# 
#         USAGE: ./iptables_manage.sh
# 
#   DESCRIPTION: 基于IPTABLES实现交互插入\删除INPUT链端口规则
# 
#  ORGANIZATION: dqzboy.com
#       CREATED: 2023
#===============================================================================

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# 函数：禁止IP访问
function block_ip {
    read -e -p "$(echo -e ${GREEN}"输入要屏蔽的IP地址: "${NC})" ip
    if sudo iptables -L INPUT -v -n | grep -q "$ip"; then
        echo -e "${RED}IP $ip 已被屏蔽。${NC}"
    else
        sudo iptables -I INPUT -s "$ip" -j DROP
        echo -e "${GREEN}IP $ip 已被屏蔽。${NC}"
    fi
}

# 函数：放通IP访问
function allow_ip {
    read -e -p "$(echo -e ${GREEN}"输入要放通的IP地址: "${NC})" ip
    if sudo iptables -L INPUT -v -n | grep -q "$ip"; then
        sudo iptables -D INPUT -s "$ip" -j DROP
        echo -e "${GREEN}IP $ip 已被放通。${NC}"
    else
        echo -e "${RED}IP $ip 没有被屏蔽，无需放通。${NC}"
    fi
}

# 函数：禁止端口访问
function block_port {
    read -e -p "$(echo -e ${GREEN}"输入要屏蔽的端口号: "${NC})" port
    if sudo iptables -L INPUT -v -n | grep -q "dpt:$port .* DROP"; then
        echo -e "${RED}端口 $port 已被屏蔽。${NC}"
    else
        sudo iptables -A INPUT -p tcp --dport "$port" -j DROP
        echo -e "${GREEN}端口 $port 已被屏蔽。${NC}"
    fi
}

# 函数：放通端口访问
function allow_port {
    read -e -p "$(echo -e ${GREEN}"输入要放通的端口号: "${NC})" port
    if sudo iptables -L INPUT -v -n | grep -q "dpt:$port .* DROP"; then
        sudo iptables -D INPUT -p tcp --dport "$port" -j DROP
        echo -e "${GREEN}端口 $port 已被放通。${NC}"
    else
        echo -e "${RED}端口 $port 没有被屏蔽，无需放通。${NC}"
    fi
}

# 显示菜单
function show_menu {
    echo -e "${GREEN}IP和端口管理菜单${NC}"
    echo "1) 禁止IP访问"
    echo "2) 放通IP访问"
    echo "3) 禁止端口访问"
    echo "4) 放通端口访问"
    echo "5) 退出"
}

# 主循环
while true; do
    show_menu
    read -e -p "$(echo -e ${GREEN}"请选择操作（1-5）: "${NC})" choice
    
    case "$choice" in
        1)
            block_ip
            ;;
        2)
            allow_ip
            ;;
        3)
            block_port
            ;;
        4)
            allow_port
            ;;
        5)
            break
            ;;
        *)
            echo -e "${RED}无效选择，请输入1-5之间的数字。${NC}"
            ;;
    esac
done
