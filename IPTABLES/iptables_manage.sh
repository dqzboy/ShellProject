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

# 函数：显示所有 jails
function show_jails {
    echo -e "${GREEN}当前激活的 jails:${NC}"
    sudo fail2ban-client status
}

# 函数：查看特定 jail 中的封禁 IP 列表
function show_jail_status {
    # 获取当前激活的 jails 列表
    local jails_list=$(sudo fail2ban-client status | grep "Jail list:" | cut -d':' -f2 | tr -d '[:space:]')
    local jails_array=(${jails_list//,/ })

    if [ ${#jails_array[@]} -eq 0 ]; then
        echo -e "${RED}没有找到激活的 jails。${NC}"
        return
    fi

    echo -e "${GREEN}当前激活的 jails:${NC}"
    for i in "${!jails_array[@]}"; do
        echo "$((i+1))) ${jails_array[$i]}"
    done

    read -e -p "$(echo -e ${GREEN}"请选择一个 jail (输入编号): "${NC})" selection

    # 验证输入是否为数字且在范围内
    if ! [[ $selection =~ ^[0-9]+$ ]] || [ $selection -lt 1 ] || [ $selection -gt ${#jails_array[@]} ]; then
        echo -e "${RED}无效的选择，返回主菜单。${NC}"
        return
    fi

    local jail=${jails_array[$((selection-1))]}
    sudo fail2ban-client status "$jail"
}

# 函数：解除特定 jail 中一个或多个 IP 的封禁
function unban_ip {
    local jails_list=$(sudo fail2ban-client status | grep "Jail list:" | cut -d':' -f2 | tr -d '[:space:]')
    local jails_array=(${jails_list//,/ })

    if [ ${#jails_array[@]} -eq 0 ]; then
        echo -e "${RED}没有找到激活的 jails。${NC}"
        return
    fi

    echo -e "${GREEN}当前激活的 jails:${NC}"
    for i in "${!jails_array[@]}"; do
        echo "$((i+1))) ${jails_array[$i]}"
    done

    read -e -p "$(echo -e ${GREEN}"请选择一个 jail (输入编号): "${NC})" selection

    if ! [[ $selection =~ ^[0-9]+$ ]] || [ $selection -lt 1 ] || [ $selection -gt ${#jails_array[@]} ]; then
        echo -e "${RED}无效的选择，返回主菜单。${NC}"
        return
    fi

    local jail=${jails_array[$((selection-1))]}
    
    read -e -p "$(echo -e ${GREEN}"输入要解封的IP地址，如果有多个请用空格分隔: "${NC})" -a ips
    if [[ ${#ips[@]} -eq 0 ]]; then
        echo -e "${RED}至少需要输入一个IP地址。${NC}"
        return
    fi

    for ip in "${ips[@]}"
    do
        echo -e "${GREEN}正在解封 $ip 从 $jail...${NC}"
        sudo fail2ban-client set "$jail" unbanip "$ip"
    done
}

# 显示表格样式的菜单
function show_menu {
    echo -e "${GREEN}Fail2Ban 管理菜单${NC}"
    echo "+-------------------+-------------------+"
    echo "| 选项 | 描述                           |"
    echo "+-------------------+-------------------+"
    echo "| 1    | 显示所有 jails                 |"
    echo "| 2    | 查看指定 jail 的信息           |"
    echo "| 3    | 解除指定 jail 封禁的 IP        |"
    echo "| 4    | 退出                           |"
    echo "+-------------------+-------------------+"
}

# 主菜单
while true; do
    show_menu
    while true; do
        read -e -p "$(echo -e ${GREEN}"请选择操作（1-4）: "${NC})" choice
        if [[ -z "$choice" ]]; then
            echo -e "${RED}选择不能为空，请重新输入。${NC}"
        elif [[ ! $choice =~ ^[1-4]$ ]]; then
            echo -e "${RED}无效选择，必须为1-4之间的数字，请重新输入。${NC}"
        else
            break
        fi
    done
    
    case "$choice" in
        1)
            show_jails
            ;;
        2)
            show_jail_status
            ;;
        3)
            unban_ip
            ;;
        4)
            break
            ;;
    esac
    # 在执行完一个有效的选项后询问用户是否继续
    while true; do
        read -e -p "$(echo -e ${GREEN}"是否继续其他操作？(y/n): "${NC})" cont
        case $cont in
            [Yy]* ) break;;
            [Nn]* ) exit;;
            * ) echo -e "${RED}请输入 y 或 n。${NC}";;
        esac
    done
done
