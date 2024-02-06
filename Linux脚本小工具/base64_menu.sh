#!/usr/bin/env bash
#===============================================================================
#
#          FILE: base64_menu.sh
# 
#         USAGE: ./base64_menu.sh
# 
#   DESCRIPTION: 用于实现base64加密和解密用户输入的内容
# 
#  ORGANIZATION: Ding Qinzheng   www.dqzboy.com
#       CREATED: 2023
#===============================================================================

GREEN="\033[1;32m"
RESET="\033[0m"
PURPLE="\033[35m"
BOLD="\033[1m"
CYAN="\033[1;36m"
RED="\033[1;31m"
# 加密函数
encrypt() {
    read -e -p "$(echo -e ${GREEN}请输入要加密的内容: ${RESET})" text_to_encrypt
    if [[ -z "$text_to_encrypt" ]]; then
        echo -e "${RED}输入内容不能为空！${RESET}"
        return 1
    fi
    echo -e "${CYAN}加密结果为: $(echo -n "$text_to_encrypt" | base64)${RESET}"
    return 0
}
# 解密函数
decrypt() {
    read -e -p "$(echo -e ${GREEN}请输入要解密的base64内容: ${RESET})" text_to_decrypt
    if [[ -z "$text_to_decrypt" ]]; then
        echo -e "${RED}输入内容不能为空！${RESET}"
        return 1
    fi
    echo -e "${CYAN}解密结果为: $(echo -n "$text_to_decrypt" | base64 --decode)${RESET}"
    return 0
}
# 脚本主体
while true; do
    echo -e "${PURPLE}=====================${RESET}"
    echo -e "${PURPLE}=     ${BOLD}菜单选项${RESET}${PURPLE}      =${RESET}"
    echo -e "${PURPLE}=====================${RESET}"
    echo -e " ${BOLD}1.${RESET} 加密"
    echo -e " ${BOLD}2.${RESET} 解密"
    echo -e " ${BOLD}3.${RESET} 退出"
    echo -e "${PURPLE}=====================${RESET}"
    read -e -p "$(echo -e ${GREEN}选择操作: ${RESET})" option
    case "$option" in
        1)
            encrypt
            [[ $? -eq 0 ]] && exit 0  # 如果加密成功则退出脚本
            ;;
        2)
            decrypt
            [[ $? -eq 0 ]] && exit 0  # 如果解密成功则退出脚本
            ;;
        3)
            echo -e "${CYAN}退出程序...${RESET}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项，请重新选择。${RESET}"
            ;;
    esac
done
