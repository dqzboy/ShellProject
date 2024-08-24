#!/bin/bash

# 检查是否以root权限运行
if [[ $EUID -ne 0 ]]; then
   echo "此脚本必须以root权限运行" 
   exit 1
fi

# 检查iptables是否存在
if ! command -v iptables &> /dev/null
then
    echo "iptables 未安装. 请安装后再运行此脚本."
    exit 1
fi

# 定义iptables命令路径
IPTABLES=$(which iptables)

# 定义黑白名单链
BLACKLIST_CHAIN="IP_BLACKLIST"
WHITELIST_CHAIN="IP_WHITELIST"

# 获取链的中文名称
get_chain_name() {
    local chain=$1
    case $chain in
        $BLACKLIST_CHAIN) echo "黑名单" ;;
        $WHITELIST_CHAIN) echo "白名单" ;;
        *) echo "未知名单" ;;
    esac
}

# 创建黑白名单链
create_chains() {
    $IPTABLES -N $BLACKLIST_CHAIN 2>/dev/null
    $IPTABLES -N $WHITELIST_CHAIN 2>/dev/null
}

# 检查IP格式
check_ip() {
    local ip=$1
    local ipv4_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    local ipv6_regex='^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$'
    
    if [[ $ip =~ $ipv4_regex ]] || [[ $ip =~ $ipv6_regex ]]; then
        return 0
    else
        return 1
    fi
}

# 检查IP是否已存在于链中
ip_exists_in_chain() {
    local ip=$1
    local chain=$2
    local action=$3
    $IPTABLES -C $chain -s $ip -j $action &>/dev/null
    return $?
}

# 清空链
clear_chain() {
    local chain=$1
    $IPTABLES -F $chain
}

# 添加IP到链
add_ip_to_chain() {
    local ip=$1
    local chain=$2
    local action=$3
    local chain_name=$(get_chain_name $chain)
    if ! ip_exists_in_chain $ip $chain $action; then
        $IPTABLES -A $chain -s $ip -j $action
        echo "已添加 $ip 到$(get_chain_name $chain)"
    else
        echo "$ip 已存在于$(get_chain_name $chain)，跳过添加"
    fi
}

# 主菜单
main_menu() {
    echo "请选择操作："
    echo "1) 设置白名单"
    echo "2) 设置黑名单"
    echo "3) 退出"
    read -e -p "请输入选项 (1-3): " choice
    
    case $choice in
        1) handle_whitelist ;;
        2) handle_blacklist ;;
        3) exit 0 ;;
        *) echo "无效选项"; main_menu ;;
    esac
}

# 处理白名单
handle_whitelist() {
    if ! $IPTABLES -L $WHITELIST_CHAIN >/dev/null 2>&1; then
        $IPTABLES -N $WHITELIST_CHAIN
    fi
    
    if $IPTABLES -C INPUT -j $BLACKLIST_CHAIN >/dev/null 2>&1; then
        read -e -p "当前使用黑名单模式，是否切换到白名单模式？(y/n): " switch
        if [[ $switch == "y" ]]; then
            $IPTABLES -D INPUT -j $BLACKLIST_CHAIN
            clear_chain $BLACKLIST_CHAIN
            # 移除之前可能存在的WHITELIST规则
            $IPTABLES -D INPUT -j $WHITELIST_CHAIN 2>/dev/null
        else
            main_menu
            return
        fi
    fi
    
    # 清空WHITELIST链
    clear_chain $WHITELIST_CHAIN
    
    # 允许本地回环
    add_ip_to_chain 127.0.0.1 $WHITELIST_CHAIN ACCEPT
    
    read -e -p "请输入白名单IP (用逗号分隔多个IP): " ips
    IFS=',' read -ra ip_array <<< "$ips"
    
    for ip in "${ip_array[@]}"; do
        if check_ip $ip; then
            add_ip_to_chain $ip $WHITELIST_CHAIN ACCEPT
        else
            echo "无效IP: $ip"
        fi
    done
    
    # 在WHITELIST链的末尾添加拒绝规则
    $IPTABLES -A $WHITELIST_CHAIN -j DROP
    
    # 确保INPUT链中有引用WHITELIST的规则，并且位于顶部
    $IPTABLES -D INPUT -j $WHITELIST_CHAIN 2>/dev/null
    $IPTABLES -I INPUT 1 -j $WHITELIST_CHAIN
    
    echo "白名单已更新，只有指定的IP和本地回环可以访问"
    main_menu
}

# 处理黑名单
handle_blacklist() {
    if ! $IPTABLES -L $BLACKLIST_CHAIN >/dev/null 2>&1; then
        $IPTABLES -N $BLACKLIST_CHAIN
    fi
    
    if $IPTABLES -C INPUT -j $WHITELIST_CHAIN >/dev/null 2>&1; then
        read -e -p "当前使用白名单模式，是否切换到黑名单模式？(y/n): " switch
        if [[ $switch == "y" ]]; then
            $IPTABLES -D INPUT -j $WHITELIST_CHAIN
            clear_chain $WHITELIST_CHAIN
            # 移除之前可能存在的BLACKLIST规则
            $IPTABLES -D INPUT -j $BLACKLIST_CHAIN 2>/dev/null
        else
            main_menu
            return
        fi
    fi
    
    read -e -p "请输入黑名单IP (用逗号分隔多个IP): " ips
    IFS=',' read -ra ip_array <<< "$ips"
    
    for ip in "${ip_array[@]}"; do
        if check_ip $ip; then
            add_ip_to_chain $ip $BLACKLIST_CHAIN DROP
        else
            echo "无效IP: $ip"
        fi
    done
    
    # 确保INPUT链中有引用BLACKLIST的规则，并且位于顶部
    $IPTABLES -D INPUT -j $BLACKLIST_CHAIN 2>/dev/null
    $IPTABLES -I INPUT 1 -j $BLACKLIST_CHAIN
    
    echo "黑名单已更新"
    main_menu
}

create_chains
main_menu
