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

# 保存 firewalld 规则的函数（不需要手动保存，firewalld 配置变更即时生效且重启服务后保留）
function save_rules {
    sudo firewall-cmd --runtime-to-permanent
    echo -e "${GREEN}规则已保存。${NC}"
}

# 函数：禁止IP访问
function block_ip {
    read -e -p "$(echo -e ${GREEN}"输入要屏蔽的IP地址(多个IP用空格分隔): "${NC})" ip
    for i in $ip; do
        if sudo firewall-cmd --list-rich-rules | grep -q "source address=\"$i\""; then
            echo -e "${RED}IP $i 已被屏蔽。${NC}"
        else
            sudo firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='$i' reject"
            sudo firewall-cmd --reload
            echo -e "${GREEN}IP $i 已被屏蔽。${NC}"
        fi
    done
    save_rules
}

# 函数：禁止端口访问
function block_port {
    read -e -p "$(echo -e ${GREEN}"输入要屏蔽的端口号(多个端口用空格分隔): "${NC})" port
    for p in $port; do
        if sudo firewall-cmd --list-ports | grep -wq "$p/tcp"; then
            echo -e "${RED}端口 $p 已被屏蔽。${NC}"
        else
            sudo firewall-cmd --permanent --add-port="$p/tcp"
            sudo firewall-cmd --reload
            echo -e "${GREEN}端口 $p 已被屏蔽。${NC}"
        fi
    done
    save_rules
}

# 函数：放通IP访问
function allow_ip {
    read -e -p "$(echo -e ${GREEN}"输入要放通的IP地址(多个IP用空格分隔): "${NC})" ips
    for ip in $ips; do
        if sudo firewall-cmd --list-rich-rules | grep -q "source address=\"$ip\""; then
            sudo firewall-cmd --permanent --remove-rich-rule="rule family='ipv4' source address='$ip' reject"
            sudo firewall-cmd --reload
            echo -e "${GREEN}IP $ip 已被放通。${NC}"
        else
            echo -e "${RED}IP $ip 没有被屏蔽，无需放通。${NC}"
        fi
    done
}

# 函数：放通端口访问
function allow_port {
    read -e -p "$(echo -e ${GREEN}"输入要放通的端口号(多个端口用空格分隔): "${NC})" ports
    for port in $ports; do
        if sudo firewall-cmd --list-ports | grep -wq "$port/tcp"; then
            sudo firewall-cmd --permanent --remove-port="$port/tcp"
            sudo firewall-cmd --reload
            echo -e "${GREEN}端口 $port 已被放通。${NC}"
        else
            echo -e "${RED}端口 $port 没有被屏蔽，无需放通。${NC}"
        fi
    done
}

# 函数：列出所有被禁止的IP
function list_blocked_ips {
    echo -e "${GREEN}当前被Fail2Ban封禁的IP地址：${NC}"
    # 获取所有 f2b-* ipset 列表名称
    local ipsets=$(sudo ipset list | grep "Name: f2b-" | cut -d' ' -f2)
    for ipset in $ipsets; do
        # 显示每个 ipset 的名称（即 jail 名称）
        echo -e "${GREEN}Jail (ipset): ${NC}$ipset"
        # 列出该 ipset 中的被封禁 IP 地址
        sudo ipset list "$ipset" | grep -Eo "([0-9]{1,3}[\.]){3}[0-9]{1,3}"
        echo "" # 为了美观，在不同 jail 的输出之间添加空行
    done
}


# 显示菜单
function show_menu {
    echo -e "${GREEN}IP和端口管理菜单${NC}"
    echo "+------------------------------+"
    echo "| 选项 | 描述                  |"
    echo "+------------------------------+"
    echo "| 1    | 禁止IP访问            |"
    echo "| 2    | 禁止端口访问          |"
    echo "| 3    | 放通IP访问            |"
    echo "| 4    | 放通端口访问          |"
    echo "| 5    | 列出所有被禁止的IP    |"
    echo "| 6    | 退出                  |"
    echo "+------------------------------+"
}


# 主循环
while true; do
    show_menu
    read -e -p "$(echo -e ${GREEN}"请选择操作（1-6）: "${NC})" choice

    case "$choice" in
        1)
            block_ip
            ;;
        2)
            block_port
            ;;
        3)
            allow_ip
            ;;
        4)
            allow_port
            ;;
        5)
            list_blocked_ips
            ;;
        6)
            break
            ;;
        *)
            echo -e "${RED}无效选择，请输入1-7之间的数字。${NC}"
            ;;
    esac
done
