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

# 加载并修改 .nmconnection 文件中的 IP 地址
function modify_connection_file() {
    local connection_file="/etc/NetworkManager/system-connections/$1.nmconnection"
    local user_input_ip="$2"

    if [ -f "$connection_file" ]; then
        # 备份原始 .nmconnection 文件
        cp "$connection_file" "$connection_file.bak"

        # 使用用户输入的 IP 地址修改 IPv4 地址
	sed -i -E "s/address1=([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/address1=$user_input_ip/" "$connection_file"
        echo -e "${GREEN_LIGHT}已将 $1.nmconnection 文件的 IP 地址修改为：$user_input_ip${NC}"
    else
        echo -e "${GREEN_LIGHT}错误：找不到 $1.nmconnection 文件。${NC}"
        exit 1
    fi
}


# 重新加载指定的网卡配置文件
function reload_connection() {
    local interface="$1"
    nmcli connection reload "$interface"
    echo -e "${GREEN_LIGHT}已重新加载 $interface 的网络配置。${NC}"
}

# 提示用户输入 IP 地址
function prompt_for_ip() {
    local interface="$1"
    read -p "$(echo -e "${GREEN_LIGHT}请输入 $interface 的新 IP 地址：${NC}")" new_ip

    # 检查用户输入的是否是有效的 IP 地址
    if [[ $new_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        modify_connection_file "$interface" "$new_ip"
        reload_connection "$interface"

        # 断开并重新连接网络接口
        nmcli connection down "$interface" && nmcli connection up "$interface"
    else
        echo -e "${GREEN_LIGHT}错误：无效的 IP 地址格式。请输入一个有效的 IPv4 地址。${NC}"
        exit 1
    fi
}

# 获取当前活动的网络接口名称
active_interface=$(nmcli device status | grep -E '\sconnected\s' | awk '{print $1}')

# 提示用户使用修改后的IP地址连接服务器
if [ -n "$active_interface" ]; then
    display_connect_instructions "$active_interface" "$new_ip"
    prompt_for_ip "$active_interface"
else
    echo -e "${GREEN_LIGHT}错误：未找到活动的网络接口。${NC}"
    display_interfaces
    exit 1
fi
