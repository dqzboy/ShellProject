#!/usr/bin/env bash
#===============================================================================
#
#          FILE: improved_iptables_blackwhite_list.sh
# 
#         USAGE: ./improved_iptables_blackwhite_list.sh
# 
#   DESCRIPTION: 基于IPTABLES实现交互黑白名单管理，支持IP批量添加、删除，黑白名单列表查询
# 
#  ORGANIZATION: dqzboy.com DingQinzheng
#       CREATED: 2024.08
#===============================================================================


GREEN="\033[0;32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"
BLUE="\033[0;34m"
MAGENTA="\033[0;35m"
CYAN="\033[0;36m"
WHITE="\033[1;37m"
BLACK="\033[0;30m"
PINK="\033[0;95m"
LIGHT_GREEN="\033[1;32m"
LIGHT_RED="\033[1;31m"
LIGHT_YELLOW="\033[1;33m"
LIGHT_BLUE="\033[1;34m"
LIGHT_MAGENTA="\033[1;35m"
LIGHT_CYAN="\033[1;36m"
LIGHT_PINK="\033[1;95m"
BRIGHT_CYAN="\033[96m"
BOLD="\033[1m"
UNDERLINE="\033[4m"
BLINK="\033[5m"
REVERSE="\033[7m"

INFO="[${GREEN}INFO${RESET}]"
ERROR="[${RED}ERROR${RESET}]"
WARN="[${YELLOW}WARN${RESET}]"
function INFO() {
    echo -e "${INFO} ${1}"
}
function ERROR() {
    echo -e "${ERROR} ${1}"
}
function WARN() {
    echo -e "${WARN} ${1}"
}

function PROMPT_Y_N() {
    echo -e "[${LIGHT_GREEN}y${RESET}/${LIGHT_BLUE}n${RESET}]: "
}

PROMPT_YES_NO=$(PROMPT_Y_N)

function SEPARATOR() {
    echo -e "${INFO}${BOLD}${LIGHT_BLUE}======================== ${1} ========================${RESET}"
}

# 检查是否以root权限运行
if [[ $EUID -ne 0 ]]; then
   echo "此脚本必须以root权限运行" 
   exit 1
fi

function IP_BLACKWHITE_LIST() {
    if ! command -v iptables &> /dev/null
    then
        WARN "iptables 未安装. 请安装后再运行此脚本."
        exit 1
    fi
    IPTABLES=$(which iptables)

    BLACKLIST_CHAIN="IP_BLACKLIST"
    WHITELIST_CHAIN="IP_WHITELIST"
    WHITELIST_FILE="/etc/firewall/whitelist.txt"
    BLACKLIST_FILE="/etc/firewall/blacklist.txt"

    # 确保文件存在
    mkdir -p /etc/firewall
    touch $WHITELIST_FILE $BLACKLIST_FILE

    get_chain_name() {
        local chain=$1
        case $chain in
            $BLACKLIST_CHAIN) echo "黑名单" ;;
            $WHITELIST_CHAIN) echo "白名单" ;;
            *) echo "未知名单" ;;
        esac
    }

    create_chains() {
        $IPTABLES -N $BLACKLIST_CHAIN 2>/dev/null
        $IPTABLES -N $WHITELIST_CHAIN 2>/dev/null
    }

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

    ip_exists_in_file() {
        local ip=$1
        local file=$2
        grep -q "^$ip$" "$file"
        return $?
    }

    add_ips_to_file() {
        local ips=("$@")
        local file="${ips[-1]}"
        unset 'ips[-1]'
        local chain_name=$(get_chain_name $([[ $file == $WHITELIST_FILE ]] && echo $WHITELIST_CHAIN || echo $BLACKLIST_CHAIN))
        local added=()
        local skipped=()

        for ip in "${ips[@]}"; do
            if ! ip_exists_in_file $ip $file; then
                echo $ip >> "$file"
                added+=("$ip")
            else
                skipped+=("$ip")
            fi
        done

        if [ ${#added[@]} -gt 0 ]; then
            INFO "${LIGHT_BLUE}${added[*]}${RESET} ${LIGHT_GREEN}已添加${RESET}到$chain_name"
        fi
        if [ ${#skipped[@]} -gt 0 ]; then
            WARN "${LIGHT_BLUE}${skipped[*]}${RESET} ${LIGHT_YELLOW}已存在${RESET}于$chain_name，跳过添加"
        fi
    }

    remove_ips_from_file() {
        local ips=("$@")
        local file="${ips[-1]}"
        unset 'ips[-1]'
        local chain_name=$(get_chain_name $([[ $file == $WHITELIST_FILE ]] && echo $WHITELIST_CHAIN || echo $BLACKLIST_CHAIN))
        local removed=()
        local not_found=()

        for ip in "${ips[@]}"; do
            if ip_exists_in_file $ip $file; then
                sed -i "/^$ip$/d" "$file"
                removed+=("$ip")
            else
                not_found+=("$ip")
            fi
        done

        if [ ${#removed[@]} -gt 0 ]; then
            INFO "${LIGHT_BLUE}${removed[*]}${RESET} ${LIGHT_RED}已从${RESET}$chain_name${LIGHT_RED}移除${RESET}"
        fi
        if [ ${#not_found[@]} -gt 0 ]; then
            WARN "${LIGHT_BLUE}${not_found[*]}${RESET} ${LIGHT_YELLOW}不存在${RESET}于$chain_name，无需移除"
        fi
    }

    list_ips_in_file() {
        local file=$1
        local chain_name=$(get_chain_name $([[ $file == $WHITELIST_FILE ]] && echo $WHITELIST_CHAIN || echo $BLACKLIST_CHAIN))

        echo "---------------------------------------------------------------"
        echo "当前${chain_name}中的IP列表："
        cat "$file"
    }

    apply_ip_list() {
        local chain=$1
        local file=$2
        local action=$3

        # 清空链
        $IPTABLES -F $chain

        # 使用 iptables-restore 批量应用规则
        {
            echo "*filter"
            echo ":$chain - [0:0]"
            while IFS= read -r ip; do
                echo "-A $chain -s $ip -j $action"
            done < "$file"
            echo "COMMIT"
        } | $IPTABLES-restore -n
    }

    ensure_default_deny_for_whitelist() {
        if ! $IPTABLES -C $WHITELIST_CHAIN -j DROP &>/dev/null; then
            $IPTABLES -A $WHITELIST_CHAIN -j DROP
            INFO "已添加默认拒绝规则到白名单"
        fi
    }

    whitelist_is_empty() {
        [ ! -s "$WHITELIST_FILE" ]
    }

    apply_whitelist() {
        if whitelist_is_empty; then
            WARN "白名单为空，不应用白名单规则以避免锁定系统。"
            return 1
        fi

        if ! $IPTABLES -C INPUT -j $WHITELIST_CHAIN &>/dev/null; then
            $IPTABLES -I INPUT 1 -j $WHITELIST_CHAIN
            INFO "已将白名单规则应用到 INPUT 链"
        else
            INFO "白名单规则已经应用到 INPUT 链"
        fi
        apply_ip_list $WHITELIST_CHAIN $WHITELIST_FILE ACCEPT
        ensure_default_deny_for_whitelist
        return 0
    }

    switch_to_whitelist() {
        $IPTABLES -D INPUT -j $BLACKLIST_CHAIN 2>/dev/null
        if apply_whitelist; then
            INFO "${LIGHT_YELLOW}已切换到白名单模式${RESET}"
        else
            WARN "${LIGHT_YELLOW}无法切换到白名单模式，请先添加 IP 到白名单${RESET}"
        fi
    }

    switch_to_blacklist() {
        $IPTABLES -D INPUT -j $WHITELIST_CHAIN 2>/dev/null
        $IPTABLES -I INPUT 1 -j $BLACKLIST_CHAIN
        apply_ip_list $BLACKLIST_CHAIN $BLACKLIST_FILE DROP
        INFO "${LIGHT_YELLOW}已切换到黑名单模式${RESET}"
    }

    handle_whitelist() {
        create_chains

        local whitelist_mode_active=false
        if $IPTABLES -C INPUT -j $WHITELIST_CHAIN &>/dev/null; then
            whitelist_mode_active=true
        elif $IPTABLES -C INPUT -j $BLACKLIST_CHAIN &>/dev/null; then
            read -e -p "$(WARN "${LIGHT_YELLOW}当前使用黑名单模式${RESET},${LIGHT_CYAN}是否切换到白名单模式？(y/n)${RESET}: ")" switch
            if [[ $switch == "y" ]]; then
                whitelist_mode_active=false
            else
                return
            fi
        fi

        while true; do
            echo "---------------------------------------------------------------"
            echo -e "1) ${BOLD}添加IP到白名单${RESET}"
            echo -e "2) ${BOLD}从白名单移除IP${RESET}"
            echo -e "3) ${BOLD}查看当前白名单${RESET}"
            echo -e "4) ${BOLD}应用白名单规则${RESET}"
            echo -e "5) ${BOLD}返回上一级${RESET}"
            echo "---------------------------------------------------------------"
            read -e -p "$(INFO "输入${LIGHT_CYAN}对应数字${RESET}并按${LIGHT_GREEN}Enter${RESET}键 > ")" whitelist_choice

            case $whitelist_choice in
                1)
                    read -e -p "$(INFO "${LIGHT_CYAN}请输入要添加到白名单的IP (用逗号分隔多个IP)${RESET}: ")" ips
                    IFS=',' read -ra ip_array <<< "$ips"
                    valid_ips=()
                    for ip in "${ip_array[@]}"; do
                        if check_ip $ip; then
                            valid_ips+=("$ip")
                        else
                            WARN "无效IP: $ip"
                        fi
                    done
                    if [ ${#valid_ips[@]} -gt 0 ]; then
                        add_ips_to_file "${valid_ips[@]}" "$WHITELIST_FILE"
                    fi
                    ;;
                2)
                    read -e -p "$(INFO "${LIGHT_CYAN}请输入要从白名单移除的IP (用逗号分隔多个IP)${RESET}: ")" ips
                    IFS=',' read -ra ip_array <<< "$ips"
                    valid_ips=()
                    for ip in "${ip_array[@]}"; do
                        if check_ip $ip; then
                            valid_ips+=("$ip")
                        else
                            WARN "无效IP: $ip"
                        fi
                    done
                    if [ ${#valid_ips[@]} -gt 0 ]; then
                        remove_ips_from_file "${valid_ips[@]}" "$WHITELIST_FILE"
                    fi
                    ;;
                3)
                    list_ips_in_file $WHITELIST_FILE
                    ;;
                4)
                    if apply_whitelist; then
                        whitelist_mode_active=true
                    fi
                    ;;
                5)
                    if ! $whitelist_mode_active; then
                        read -e -p "$(WARN "${LIGHT_YELLOW}白名单规则尚未应用。您确定要退出吗？${RESET} (y/n): ")" confirm
                        if [[ $confirm != "y" ]]; then
                            continue
                        fi
                    fi
                    return
                    ;;
                *)
                    WARN "输入了无效的选择。请重新${LIGHT_GREEN}选择1-5${RESET}的选项."
                    ;;
            esac
        done
    }

    handle_blacklist() {
        create_chains

        local blacklist_mode_active=false
        if $IPTABLES -C INPUT -j $BLACKLIST_CHAIN &>/dev/null; then
            blacklist_mode_active=true
        elif $IPTABLES -C INPUT -j $WHITELIST_CHAIN &>/dev/null; then
            read -e -p "$(WARN "${LIGHT_YELLOW}当前使用白名单模式${RESET},${LIGHT_CYAN}是否切换到黑名单模式？(y/n)${RESET}: ")" switch
            if [[ $switch == "y" ]]; then
                switch_to_blacklist
                blacklist_mode_active=true
            else
                return
            fi
        else
            switch_to_blacklist
            blacklist_mode_active=true
        fi

        while true; do
            echo "---------------------------------------------------------------"
            echo -e "1) ${BOLD}添加IP到黑名单${RESET}"
            echo -e "2) ${BOLD}从黑名单移除IP${RESET}"
            echo -e "3) ${BOLD}查看当前黑名单${RESET}"
            echo -e "4) ${BOLD}返回上一级${RESET}"
            echo "---------------------------------------------------------------"
            read -e -p "$(INFO "输入${LIGHT_CYAN}对应数字${RESET}并按${LIGHT_GREEN}Enter${RESET}键 > ")" blacklist_choice

            case $blacklist_choice in
                1)
                    read -e -p "$(INFO "${LIGHT_CYAN}请输入要添加到黑名单的IP (用逗号分隔多个IP)${RESET}: ")" ips
                    IFS=',' read -ra ip_array <<< "$ips"
                    valid_ips=()
                    for ip in "${ip_array[@]}"; do
                        if check_ip $ip; then
                            valid_ips+=("$ip")
                        else
                            WARN "无效IP: $ip"
                        fi
                    done
                    if [ ${#valid_ips[@]} -gt 0 ]; then
                        add_ips_to_file "${valid_ips[@]}" "$BLACKLIST_FILE"
                        apply_ip_list $BLACKLIST_CHAIN $BLACKLIST_FILE DROP
                    fi
                    ;;
                2)
                    read -e -p "$(INFO "${LIGHT_CYAN}请输入要从黑名单移除的IP (用逗号分隔多个IP)${RESET}: ")" ips
                    IFS=',' read -ra ip_array <<< "$ips"
                    valid_ips=()
                    for ip in "${ip_array[@]}"; do
                        if check_ip $ip; then
                            valid_ips+=("$ip")
                        else
                            WARN "无效IP: $ip"
                        fi
                    done
                    if [ ${#valid_ips[@]} -gt 0 ]; then
                        remove_ips_from_file "${valid_ips[@]}" "$BLACKLIST_FILE"
                        apply_ip_list $BLACKLIST_CHAIN $BLACKLIST_FILE DROP
                    fi
                    ;;
                3)
                    list_ips_in_file $BLACKLIST_FILE
                    ;;
                4)
                    return
                    ;;
                *)
                    WARN "输入了无效的选择。请重新${LIGHT_GREEN}选择1-4${RESET}的选项."
                    ;;
            esac
        done
    }

while true; do
        SEPARATOR "设置IP黑白名单"
        echo -e "1) ${BOLD}管理${LIGHT_GREEN}白名单${RESET}"
        echo -e "2) ${BOLD}管理${LIGHT_CYAN}黑名单${RESET}"
        echo -e "3) ${BOLD}返回${LIGHT_RED}主菜单${RESET}"
        echo -e "0) ${BOLD}退出脚本${RESET}"
        echo "---------------------------------------------------------------"
        read -e -p "$(INFO "输入${LIGHT_CYAN}对应数字${RESET}并按${LIGHT_GREEN}Enter${RESET}键 > ")" ipblack_choice

        case $ipblack_choice in
            1)
                handle_whitelist
                ;;
            2)
                handle_blacklist
                ;;
            3)
                return
                ;;
            0)
                exit 0
                ;;
            *)
                WARN "输入了无效的选择。请重新${LIGHT_GREEN}选择0-3${RESET}的选项."
                ;;
        esac
    done
}
IP_BLACKWHITE_LIST
