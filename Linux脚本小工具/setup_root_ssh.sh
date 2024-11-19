#!/bin/bash

# 定义颜色变量
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 输出格式化函数
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_section() {
    echo -e "\n${CYAN}=== $1 ===${NC}"
}

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then 
    print_error "请以root权限运行此脚本"
    exit 1
fi

# 设置新的root密码
set_root_password() {
    print_section "设置Root密码"
    read -ep "$(echo -e "${BLUE}请输入新的root密码: ${NC}")" root_password
    echo
    read -ep "$(echo -e "${BLUE}请再次输入root密码: ${NC}")" root_password_confirm
    echo

    if [ "$root_password" != "$root_password_confirm" ]; then
        print_error "两次输入的密码不匹配"
        exit 1
    fi
    
    # 修改root密码
    echo "root:$root_password" | chpasswd
    if [ $? -eq 0 ]; then
        print_success "root密码修改成功"
    else
        print_error "root密码修改失败"
        exit 1
    fi
}

# 配置SSH允许root登录
configure_ssh() {
    print_section "配置SSH服务"
    print_info "正在修改SSH配置..."
    
    # 备份原始配置文件
    \cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    print_info "已备份原始SSH配置到: /etc/ssh/sshd_config.bak"
    
    # 修改SSH配置
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
    
    # 重启SSH服务
    print_info "正在重启SSH服务..."
    systemctl restart sshd
    
    if [ $? -eq 0 ]; then
        print_success "SSH服务配置完成并已重启"
    else
        print_error "SSH服务重启失败"
        exit 1
    fi
}

# 检查防火墙状态并确保SSH端口开放
check_firewall() {
    print_section "防火墙配置检查"
    
    if command -v ufw >/dev/null 2>&1; then
        # 检查UFW状态
        if ufw status | grep -q "Status: active"; then
            print_info "配置UFW防火墙规则..."
            ufw allow ssh
            print_success "SSH端口(22)已在UFW防火墙中开放"
        else
            print_warning "UFW防火墙未启用，无需配置"
        fi
    else
        print_warning "系统未安装UFW防火墙"
    fi
}

# 显示系统信息
show_info() {
    print_section "系统配置信息"
    echo -e "${CYAN}------------------------${NC}"
    echo -e "${BLUE}SSH状态:${NC} $(systemctl is-active sshd)"
    echo -e "${BLUE}SSH端口:${NC} $(grep "^#Port" /etc/ssh/sshd_config | awk '{print $2}')"
    echo -e "${BLUE}系统IP地址:${NC} $(hostname -I | awk '{print $1}')"
    echo -e "${CYAN}------------------------${NC}"
    print_success "配置完成！现在可以使用root账户通过SSH远程登录了。"
    
    # 显示安全提示
    print_section "安全建议"
    print_warning "1. 请确保使用强密码来保护root账户"
    print_warning "2. 建议配置SSH密钥认证来替代密码认证"
    print_warning "3. 考虑更改默认SSH端口（22）以增加安全性"
    print_warning "4. 建议安装fail2ban等工具来防止暴力破解"
}

# 主程序
main() {
    print_section "开始配置Ubuntu 22.04 Root SSH登录"
    set_root_password
    configure_ssh
    check_firewall
    show_info
}

# 执行主程序
main
