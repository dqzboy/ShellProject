#!/bin/bash
#===============================================================================
#
#          FILE: manage_chatnio_docker.sh
# 
#         USAGE: ./manage_chatnio_docker.sh
#
#   DESCRIPTION: ChatNIO项目Docker容器服务统一管理脚本。支持安装、更新、重启、卸载
# 
#===============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
NC='\033[0m' # 重置颜色

# 定义docker-compose文件路径
COMPOSE_FILE="/data/coai/docker-compose.yaml"

# 清屏函数
clear_screen() {
    clear
}

# 显示标题
show_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${CYAN}    ChatNIO Docker 服务管理脚本    ${NC}"
    echo -e "${BLUE}================================${NC}"
    echo
}

# 检查docker-compose文件是否存在
check_compose_file() {
    if [ ! -f "$COMPOSE_FILE" ]; then
        echo -e "${RED}错误: $COMPOSE_FILE 文件不存在${NC}"
        exit 1
    fi
}

# 服务操作函数
service_operation() {
    local service=$1
    local operation=$2
    
    case $operation in
        1) # 安装
            echo -e "${YELLOW}正在安装 $service ...${NC}"
            docker-compose -f $COMPOSE_FILE up -d $service
            ;;
        2) # 更新
            echo -e "${YELLOW}正在更新 $service ...${NC}"
            docker-compose -f $COMPOSE_FILE pull $service
            docker-compose -f $COMPOSE_FILE up -d $service
            ;;
        3) # 重启
            echo -e "${YELLOW}正在重启 $service ...${NC}"
            docker-compose -f $COMPOSE_FILE restart $service
            ;;
        4) # 卸载
            echo -e "${RED}正在卸载 $service ...${NC}"
            docker-compose -f $COMPOSE_FILE stop $service
            docker-compose -f $COMPOSE_FILE rm -f $service
            ;;
        *)
            echo -e "${RED}无效的操作选择${NC}"
            return 1
            ;;
    esac

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}操作成功完成！${NC}"
    else
        echo -e "${RED}操作失败！${NC}"
    fi
}

# 显示操作菜单
show_operation_menu() {
    local service=$1
    while true; do
        clear_screen
        show_header
        echo -e "${CYAN}当前服务: ${PURPLE}$service${NC}"
        echo -e "${GRAY}请选择要执行的操作:${NC}"
        echo -e "${GREEN}1) 安装服务${NC}"
        echo -e "${BLUE}2) 更新服务${NC}"
        echo -e "${YELLOW}3) 重启服务${NC}"
        echo -e "${RED}4) 卸载服务${NC}"
        echo -e "${GRAY}0) 返回主菜单${NC}"
        
        read -ep $'\033[36m请输入选项数字: \033[0m' choice

        case $choice in
            [1-4])
                service_operation $service $choice
                read -n 1 -p "按任意键继续..."
                ;;
            0)
                return 0
                ;;
            *)
                echo -e "${RED}无效的选择，请重试${NC}"
                read -n 1 -p "按任意键继续..."
                ;;
        esac
    done
}

# 主菜单
main_menu() {
    while true; do
        clear_screen
        show_header
        echo -e "${GRAY}请选择要管理的服务:${NC}"
        echo -e "${CYAN}1) ChatNIO 主程序    (端口: 8000)${NC}"
        echo -e "${CYAN}2) MySQL 数据库      (端口: 3306)${NC}"
        echo -e "${CYAN}3) Redis 缓存        (端口: 6379)${NC}"
        echo -e "${RED}0) 退出脚本${NC}"
        
        read -ep $'\033[36m请输入选项数字: \033[0m' choice
        
        case $choice in
            1)  show_operation_menu "chatnio" ;;
            2)  show_operation_menu "mysql" ;;
            3)  show_operation_menu "redis" ;;
            0)
                echo -e "${GREEN}感谢使用，再见！${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效的选择，请重试${NC}"
                read -n 1 -p "按任意键继续..."
                ;;
        esac
    done
}

# 检查是否为root用户
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}错误: 此脚本需要root权限运行${NC}"
    echo -e "${YELLOW}请使用 sudo 或 root 用户运行此脚本${NC}"
    exit 1
fi

# 检查docker是否安装
if ! command -v docker &> /dev/null; then
    echo -e "${RED}错误: docker 未安装${NC}"
    exit 1
fi

# 检查docker-compose是否安装
if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}错误: docker-compose 未安装${NC}"
    exit 1
fi

# 检查compose文件
check_compose_file

# 运行主菜单
main_menu
