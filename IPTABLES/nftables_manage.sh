#!/usr/bin/env bash
#===============================================================================
#
#          FILE: nftables_manage.sh
# 
#         USAGE: ./nftables_manage.sh
# 
#   DESCRIPTION: 基于nftables实现交互插入\删除INPUT链端口\IP规则
# 
#  ORGANIZATION: Ding Qinzheng  www.dqzboy.com
#       CREATED: 2023
#===============================================================================

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# 保存 nftables 规则的函数
function save_rules {
    sudo nft list ruleset | sudo tee /etc/nftables.conf > /dev/null
    echo -e "${GREEN}规则已保存。${NC}"
}

# 函数：禁止IP访问
function block_ip {
    # 获取所有表的名称
    local tables
    IFS=$'\n' read -r -d '' -a tables < <(sudo nft list tables | awk '{$1=""; print substr($0,2)}' && printf '\0')

    echo "选择一个表进行操作:"
    select table in "${tables[@]}"; do
        if [ -n "$table" ]; then
            break
        else
            echo "无效的选择，请重新选择。"
        fi
    done

    # 检查 "input" 链是否存在于选定的表中，如果不存在就创建它
    if ! sudo nft list table $table | grep -q 'chain input'; then
        sudo nft add chain $table input { type filter hook input priority 0 \; }
    fi

    read -e -p "$(echo -e ${GREEN}"输入要屏蔽的IP地址(多个IP用空格分隔): "${NC})" ip
    for i in $ip; do
        if sudo nft list ruleset | grep -q "$i"; then
            echo -e "${RED}IP $i 已被屏蔽。${NC}"
        else
            sudo nft add rule $table input ip saddr "$i" drop
            echo -e "${GREEN}IP $i 已被屏蔽。${NC}"
        fi
    done
    save_rules
}

function block_port {
    # 获取所有表的名称
    local tables
    IFS=$'\n' read -r -d '' -a tables < <(sudo nft list tables | awk '{$1=""; print substr($0,2)}' && printf '\0')

    # 让用户选择一个表进行操作
    echo "选择一个表进行操作:"
    select table in "${tables[@]}"; do
        if [ -n "$table" ]; then
            break
        else
            echo "无效的选择，请重新选择。"
        fi
    done

    # 获取用户输入的要屏蔽的端口号
    read -e -p "$(echo -e ${GREEN}"输入要屏蔽的端口号(多个端口用空格分隔): "${NC})" port
    for p in $port; do
        # 检查端口是否已经被屏蔽
        if sudo nft list ruleset | grep -Eq "tcp dport $p drop"; then
            echo -e "${RED}端口 $p 已被屏蔽。${NC}"
        else
            # 添加规则到所选表的 "input" 链中
            sudo nft add rule $table input tcp dport "$p" drop
            echo -e "${GREEN}端口 $p 已被屏蔽。${NC}"
            save_rules
        fi
    done
}

# 函数：放通IP访问
function allow_ip {
    # 获取所有表的名称
    local tables
    IFS=$'\n' read -r -d '' -a tables < <(sudo nft list tables | awk '{$1=""; print substr($0,2)}' && printf '\0')

    echo "选择一个表进行操作:"
    select table in "${tables[@]}"; do
        if [ -n "$table" ]; then
            break
        else
            echo "无效的选择，请重新选择。"
        fi
    done

    read -e -p "$(echo -e ${GREEN}"输入要放通的IP地址(多个IP用空格分隔): "${NC})" ips
    for ip in $ips; do
        handle=$(sudo nft --handle list chain $table input | grep -oP "${ip} drop # handle \\K\\d+")
        if [ -z "$handle" ]; then
            echo -e "${RED}IP $ip 没有被屏蔽，无需放通。${NC}"
        else
            sudo nft delete rule $table input handle $handle
            echo -e "${GREEN}IP $ip 已被放通。${NC}"
            save_rules
        fi
    done
}

# 函数：放通端口访问
function allow_port {
    # 获取所有表的名称
    local tables
    IFS=$'\n' read -r -d '' -a tables < <(sudo nft list tables | awk '{$1=""; print substr($0,2)}' && printf '\0')

    echo "选择一个表进行操作:"
    select table in "${tables[@]}"; do
        if [ -n "$table" ]; then
            break
        else
            echo "无效的选择，请重新选择。"
        fi
    done

    read -e -p "$(echo -e ${GREEN}"输入要放通的端口号(多个端口用空格分隔): "${NC})" ports
    for port in $ports; do
        handle=$(sudo nft --handle list chain $table input | grep -oP "tcp dport ${port} drop # handle \\K\\d+")
        if [ -z "$handle" ]; then
            echo -e "${RED}端口 $port 没有被屏蔽，无需放通。${NC}"
        else
            sudo nft delete rule $table input handle $handle
            echo -e "${GREEN}端口 $port 已被放通。${NC}"
            save_rules
        fi
    done
}

# 函数：列出所有被禁止的IP
function list_blocked_ips {
    # 获取所有表的名称
    local tables
    IFS=$'\n' read -r -d '' -a tables < <(sudo nft list tables | awk '{$1=""; print substr($0,2)}' && printf '\0')

    # 遍历每个表
    for table in "${tables[@]}"; do
        echo -e "${GREEN}检查表: $table ${NC}"
        local sets
        IFS=$'\n' read -r -d '' -a sets < <(sudo nft list table "$table" | grep -oP '(?<=set ).*(?={)' && printf '\0')

        # 检查表下是否有集合
        if [ ${#sets[@]} -eq 0 ]; then
            echo -e "${RED}>>> 在表$table下没有找到集合${NC}"
        else
            # 遍历每个集合
            for set in "${sets[@]}"; do
                if sudo nft list set "$table" "$set" | grep -q 'ipv4_addr'; then
                    local ips
                    ips=$(sudo nft list set "$table" "$set" | grep -oP '(\d{1,3}\.){3}\d{1,3}')
                    if [ -z "$ips" ]; then
                        echo -e "${RED}>>> 在表$table中集合$set是空的${NC}"
                    else
                        echo -e "${GREEN}>>> 在表$table中被禁止的IP地址集合$set: ${NC}"
                        echo "$ips"
                    fi
                fi
            done
        fi
    done
}

# 函数：列出所有被禁止的端口
function list_blocked_ports {
    # 获取所有表的名称
    local tables
    IFS=$'\n' read -r -d '' -a tables < <(sudo nft list tables | awk '{$1=""; print substr($0,2)}' && printf '\0')

    # 遍历每个表
    for table in "${tables[@]}"; do
        echo -e "${GREEN}检查表: $table ${NC}"
        local chains
        IFS=$'\n' read -r -d '' -a chains < <(sudo nft list table "$table" | grep -oP '(?<=chain ).*(?={)' && printf '\0')

        # 检查表下是否有链
        if [ ${#chains[@]} -eq 0 ]; then
            echo -e "${RED}>>> 在表$table下没有找到链${NC}"
        else
            # 遍历每个链
            for chain in "${chains[@]}"; do
                local blocked_ports
                IFS=$'\n' read -r -d '' -a blocked_ports < <(sudo nft list chain "$table" "$chain" | grep 'drop' | grep 'dport' | awk '{print $9}' && printf '\0')
                if [ ${#blocked_ports[@]} -eq 0 ]; then
                    echo -e "${RED}>>> 在链$chain中没有被禁止的端口${NC}"
                else
                    echo -e "${GREEN}>>> 在链$chain中被禁止的端口: ${NC}"
                    printf '%s\n' "${blocked_ports[@]}" | sort | uniq
                fi
            done
        fi
    done
}

# 显示菜单
function show_menu {
    echo -e "${GREEN}IP和端口管理菜单${NC}"
    echo "+--------------------------------+"
    echo "| 选项   | 描述                  |"
    echo "+--------------------------------+"
    echo "| 1      | 禁止IP访问            |"
    echo "| 2      | 禁止端口访问          |"
    echo "| 3      | 放通IP访问            |"
    echo "| 4      | 放通端口访问          |"
    echo "| 5      | 列出所有被禁止的IP    |"
    echo "| 6      | 列出所有被禁止的端口  |"
    echo "| 7      | 退出                  |"
    echo "+--------------------------------+"
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
            allow_ip
            ;;
        4)
            allow_port
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
