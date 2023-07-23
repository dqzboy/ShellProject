#!/usr/bin/env bash
#===============================================================================
#
#          FILE: modify_ip.sh
# 
#         USAGE: ./modify_ip.sh
# 
#   DESCRIPTION: RHEL 8发行版OS 使用nmcli指令自动化修改网卡IP，配合NetworkManager使用
# 
#  ORGANIZATION: dqzboy.com
#       CREATED: 2022
#===============================================================================

echo
cat << EOF
██████╗  ██████╗ ███████╗██████╗  ██████╗ ██╗   ██╗            ██████╗ ██████╗ ███╗   ███╗
██╔══██╗██╔═══██╗╚══███╔╝██╔══██╗██╔═══██╗╚██╗ ██╔╝           ██╔════╝██╔═══██╗████╗ ████║
██║  ██║██║   ██║  ███╔╝ ██████╔╝██║   ██║ ╚████╔╝            ██║     ██║   ██║██╔████╔██║
██║  ██║██║▄▄ ██║ ███╔╝  ██╔══██╗██║   ██║  ╚██╔╝             ██║     ██║   ██║██║╚██╔╝██║
██████╔╝╚██████╔╝███████╗██████╔╝╚██████╔╝   ██║       ██╗    ╚██████╗╚██████╔╝██║ ╚═╝ ██║
╚═════╝  ╚══▀▀═╝ ╚══════╝╚═════╝  ╚═════╝    ╚═╝       ╚═╝     ╚═════╝ ╚═════╝ ╚═╝     ╚═╝
                                                                                          
EOF

# 颜色定义
GREEN_LIGHT="\033[1;32m"
RED="\033[0;31m"
CYAN="\033[0;36m"
NC="\033[0m" # 恢复默认颜色

# 显示连接服务器的提示
function display_connect_instructions() {
    local connect_instructions="${RED}脚本执行完成后,必须使用以下 IP 重新连接服务器！${NC}"
    local interface="$1"
    local new_ip="$2"

    # 构建虚线框
    local frame_length=${#connect_instructions}
    local frame=""
    for ((i=1; i<=frame_length+4; i++)); do
        frame+="-"
    done

    echo -e "${CYAN}+${frame}+${NC}"
    echo -e "${CYAN}|  ${connect_instructions}  ${CYAN}|${NC}"
    echo -e "${CYAN}+${frame}+${NC}"
}

# 显示可用的网络接口
function display_interfaces() {
    echo "可用的网络接口："
    nmcli device status
}

# 加载并修改 nmcli 连接配置为静态IP
function modify_connection() {
    local interface="$1"
    local new_ip="$2"
    local gateway="$3"
    local subnet_mask="$4"
    local dns_servers="$5"

    nmcli connection modify "$interface" ipv4.addresses "$new_ip/$subnet_mask" ipv4.gateway "$gateway" ipv4.dns "$dns_servers" ipv4.method manual connection.autoconnect yes

    # 检查是否执行成功
    if [ $? -eq 0 ]; then
        echo -e "${GREEN_LIGHT}已将 $interface 的网络配置修改为静态IP：IP地址：$new_ip，网关：$gateway，DNS服务器：$dns_servers${NC}"
    else
        echo -e "${RED}修改 $interface 的网络配置失败。请检查输入信息和网络接口是否正确，并重新执行脚本。${NC}"
        exit 1
    fi
}

# 检查用户输入的IP地址和子网掩码格式是否正确
function check_ip_format() {
    local ip="$1"

    # 使用正则表达式检查IP地址和子网掩码格式
    if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
        return 0
    else
        return 1
    fi
}

# 提示用户输入网络配置信息
function prompt_for_network_config() {
    local interface="$1"

    # 循环提示用户输入，直到格式正确
    while true; do
        read -e -p "$(echo -e "${GREEN_LIGHT}请输入 $interface 的新 IP 地址和子网掩码（格式为IP/子网掩码）：${NC}")" new_ip

        # 检查用户输入是否是有效的 IP 地址和子网掩码格式
        if check_ip_format "$new_ip"; then
            break
        else
            echo -e "${GREEN_LIGHT}错误：无效的 IP 地址和子网掩码格式。请重新输入一个有效的 IPv4 地址和子网掩码。${NC}"
        fi
    done

    read -e -p "$(echo -e "${GREEN_LIGHT}请输入 $interface 的网关地址：${NC}")" gateway
    read -e -p "$(echo -e "${GREEN_LIGHT}请输入 $interface 的DNS服务器地址（多个DNS服务器用空格分隔）：${NC}")" dns_servers

    # 解析用户输入的IP地址和子网掩码
    local new_ip_address="$(echo "$new_ip" | cut -d'/' -f1)"
    local subnet_mask="$(echo "$new_ip" | cut -d'/' -f2)"

    modify_connection "$interface" "$new_ip_address" "$gateway" "$subnet_mask" "$dns_servers"
    nmcli con down "$interface" && nmcli con up "$interface"
}

# 获取当前活动的网络接口名称
active_interface=$(nmcli device status | grep -E '\sconnected\s' | awk '{print $1}')

# 提示用户使用修改后的网络配置连接服务器
if [ -n "$active_interface" ]; then
    display_connect_instructions "$active_interface" "$new_ip"
    prompt_for_network_config "$active_interface"
else
    echo -e "${GREEN_LIGHT}错误：未找到活动的网络接口。${NC}"
    display_interfaces
    exit 1
fi
