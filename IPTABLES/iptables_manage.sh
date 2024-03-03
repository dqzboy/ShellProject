#!/usr/bin/env bash
#===============================================================================
#
#          FILE: iptables_manage.sh
# 
#         USAGE: ./iptables_manage.sh
# 
#   DESCRIPTION: 基于IPTABLES实现交互插入\删除INPUT链端口\IP规则
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
    for i in $ip; do
        if sudo iptables -L INPUT -v -n | grep -q "$i"; then
            echo -e "${RED}IP $i 已被屏蔽。${NC}"
        else
            sudo iptables -I INPUT -s "$i" -j DROP
            echo -e "${GREEN}IP $i 已被屏蔽。${NC}"
        fi
    done
}

# 函数：禁止端口访问
function block_port {
    read -e -p "$(echo -e ${GREEN}"输入要屏蔽的端口号: "${NC})" port
    for p in $port; do
        if sudo iptables -L INPUT -v -n | grep -q "dpt:$p .* DROP"; then
            echo -e "${RED}端口 $p 已被屏蔽。${NC}"
        else
            sudo iptables -A INPUT -p tcp --dport "$p" -j DROP
            echo -e "${GREEN}端口 $p 已被屏蔽。${NC}"
        fi
    done
}

# 函数：准备放通IP访问
function prepare_to_allow_ip {
    list_blocked_ips
    allow_ip
}

# 函数：放通IP访问
function allow_ip {
    read -e -p "$(echo -e ${GREEN}"输入要放通的IP地址(多个IP用空格分隔): "${NC})" ips
    for ip in $ips; do
        if sudo iptables -L INPUT -v -n | grep -q "$ip"; then
            sudo iptables -D INPUT -s "$ip" -j DROP
            echo -e "${GREEN}IP $ip 已被放通。${NC}"
        else
            echo -e "${RED}IP $ip 没有被屏蔽，无需放通。${NC}"
        fi
    done
}

# 函数：准备放通端口访问
function prepare_to_allow_port {
    list_blocked_ports
    allow_port
}

# 函数：放通端口访问
function allow_port {
    read -e -p "$(echo -e ${GREEN}"输入要放通的端口号(多个端口用空格分隔): "${NC})" ports
    for port in $ports; do
        if sudo iptables -L INPUT -v -n | grep -q "dpt:$port .* DROP"; then
            sudo iptables -D INPUT -p tcp --dport "$port" -j DROP
            echo -e "${GREEN}端口 $port 已被放通。${NC}"
        else
            echo -e "${RED}端口 $port 没有被屏蔽，无需放通。${NC}"
        fi
    done
}

# 函数：列出所有被禁止的IP
function list_blocked_ips {
    echo -e "${GREEN}当前被禁止的IP地址：${NC}"
    sudo iptables -L INPUT -v -n | grep DROP | grep -v "dpt:" | awk '{print $8}' | uniq
}

# 函数：列出所有被禁止的端口
function list_blocked_ports {
    echo -e "${GREEN}当前被禁止的端口：${NC}"
    sudo iptables -L INPUT -v -n | grep DROP | grep "dpt:" | awk '{for(i=1;i<=NF;i++) if($i ~ /dpt:/) print $(i+1)}'
}

# 显示菜单
function show_menu {
    echo -e "${GREEN}IP和端口管理菜单${NC}"
    echo "1) 禁止IP访问"
    echo "2) 禁止端口访问"
    echo "3) 准备放通IP访问"
    echo "4) 准备放通端口访问"
    echo "5) 列出所有被禁止的IP"
    echo "6) 列出所有被禁止的端口"
    echo "7) 退出"
}

# 主循环
while true; do
    show_menu
    read -e -p "$(echo -e ${GREEN}"请选择操作（1-7）: "${NC})" choice
    
    case "$choice" in
        1)
            block_ip
            ;;
        2)
            block_port
            ;;
        3)
            prepare_to_allow_ip
            ;;
        4)
            prepare_to_allow_port
            ;;
        5)
            list_blocked_ips
            ;;
        6)
            list_blocked_ports
            ;;
        7)
            break
            ;;
        *)
            echo -e "${RED}无效选择，请输入1-7之间的数字。${NC}"
            ;;
    esac
done
