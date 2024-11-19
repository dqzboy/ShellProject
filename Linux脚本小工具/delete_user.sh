#!/bin/bash
# 脚本名称: delete_user.sh
# 功能描述: 删除用户及其家目录
# 使用方法: sudo ./delete_user.sh

# 定义颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# 错误处理函数
handle_error() {
    local exit_code=$?
    echo -e "${RED}${BOLD}错误: $1${NC}"
    echo -e "${RED}退出码: $exit_code${NC}"
    exit $exit_code
}

# 日志函数
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

# 成功日志
log_success() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ${GREEN}$1${NC}"
}

# 警告日志
log_warning() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ${YELLOW}警告: $1${NC}"
}

# 打印分隔线
print_separator() {
    echo -e "${BLUE}----------------------------------------${NC}"
}

# 检查root权限
if [ "$(id -u)" != "0" ]; then
    handle_error "此脚本需要root权限执行！\n请使用 sudo $0 运行"
fi

# 显示脚本标题
print_separator
echo -e "${GREEN}${BOLD}用户删除工具${NC}"
print_separator

# 获取并显示系统用户列表（排除系统用户）
echo -e "${YELLOW}系统中的普通用户列表：${NC}"
awk -F: '$3 >= 1000 && $3 != 65534 {printf "  %s (UID: %s)\n", $1, $3}' /etc/passwd
print_separator

# 提示用户输入要删除的用户名
while true; do
    read -e -p "请输入要删除的用户名: " username
    echo

    # 检查是否输入为空
    if [ -z "$username" ]; then
        log_warning "用户名不能为空，请重新输入"
        continue
    fi

    # 检查是否为root用户
    if [ "$username" = "root" ]; then
        log_warning "禁止删除root用户！请重新输入"
        continue
    fi

    # 检查用户是否存在
    if ! id "$username" &>/dev/null; then
        log_warning "用户 ${BOLD}$username${NC} 不存在！请重新输入"
        continue
    fi

    # 检查是否为系统用户（UID < 1000）
    uid=$(id -u "$username")
    if [ "$uid" -lt 1000 ]; then
        log_warning "用户 ${BOLD}$username${NC} 是系统用户（UID: $uid），为了系统安全不建议删除"
        read -p "是否确实要删除此系统用户？(y/N) " -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            continue
        fi
    fi

    break
done

# 获取用户家目录
home_dir=$(eval echo ~$username)
if [ ! -d "$home_dir" ]; then
    log_warning "用户 ${BOLD}$username${NC} 的家目录 ${BOLD}$home_dir${NC} 不存在"
fi

# 获取用户进程信息
user_processes=$(ps -u "$username" -o pid=,cmd= 2>/dev/null)
if [ -n "$user_processes" ]; then
    log_warning "用户 ${BOLD}$username${NC} 当前有以下进程在运行:"
    echo "$user_processes" | sed 's/^/  /'
    echo
    read -p "是否要终止这些进程？(y/N) " -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "正在终止用户进程..."
        pkill -u "$username"
        sleep 1
        if ps -u "$username" >/dev/null; then
            log "使用 SIGKILL 强制终止剩余进程..."
            pkill -9 -u "$username"
        fi
    else
        handle_error "请先终止用户进程后再删除用户"
    fi
fi

# 显示用户信息
log "用户信息:"
echo -e "  用户名: ${BOLD}$username${NC}"
echo -e "  UID: $(id -u "$username")"
echo -e "  主组: $(id -gn "$username")"
echo -e "  家目录: ${BOLD}$home_dir${NC}"
echo -e "  Shell: $(getent passwd "$username" | cut -d: -f7)"
print_separator

# 获取用户所有的定时任务
if [ -f "/var/spool/cron/crontabs/$username" ]; then
    log_warning "用户有以下 crontab 任务:"
    cat "/var/spool/cron/crontabs/$username" | sed 's/^/  /'
fi

# 显示用户拥有的文件
log "检查用户文件..."
echo "用户在系统中的文件 (不包括家目录):"
find / -user "$username" -not -path "$home_dir/*" -ls 2>/dev/null | sed 's/^/  /'

# 确认删除
echo
echo -e "${RED}${BOLD}警告: 此操作将永久删除用户及其所有数据！${NC}"
read -p "确认删除用户 $username 及其家目录？(y/N) " -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "操作已取消"
    exit 0
fi

# 删除用户和家目录
log "开始删除用户..."

# 尝试使用 userdel 命令删除用户和家目录
if ! userdel -r "$username" 2>/dev/null; then
    log_warning "userdel 命令失败，尝试手动删除..."
    
    # 手动删除用户
    if ! userdel "$username" 2>/dev/null; then
        handle_error "删除用户失败"
    fi
    
    # 手动删除家目录
    if [ -d "$home_dir" ]; then
        if ! rm -rf "$home_dir" 2>/dev/null; then
            log_warning "删除家目录失败：$home_dir"
            echo "请手动检查并删除家目录"
        fi
    fi
fi

# 验证用户是否已被删除
if id "$username" &>/dev/null; then
    handle_error "用户删除失败！"
else
    log_success "用户 ${BOLD}$username${NC} 已成功删除"
fi

# 检查家目录是否已被删除
if [ -d "$home_dir" ]; then
    log_warning "家目录 ${BOLD}$home_dir${NC} 可能未完全删除，请手动检查"
else
    log_success "家目录已成功删除"
fi

# 清理系统中可能残留的用户文件
log "检查系统中是否存在用户文件残留..."
remaining_files=$(find / -user "$username" 2>/dev/null)
if [ -n "$remaining_files" ]; then
    log_warning "发现以下残留文件:"
    echo "$remaining_files" | sed 's/^/  /'
    echo "请手动检查这些文件是否需要删除"
fi

print_separator
echo -e "${GREEN}${BOLD}用户删除操作已完成！${NC}"
print_separator
