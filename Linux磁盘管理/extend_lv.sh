#!/bin/bash
# 脚本名称: extend_lv.sh
# 功能描述: 自动扩展LVM逻辑卷到卷组的最大可用空间
# 使用方法: sudo ./extend_lv.sh
# 注意: 需要root权限执行

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

# 检查root权限
if [ "$(id -u)" != "0" ]; then
    handle_error "此脚本需要root权限执行！\n请使用 sudo ./extend_lv.sh 运行"
fi

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

# 检查命令是否存在
check_command() {
    if ! command -v "$1" &> /dev/null; then
        handle_error "找不到必需的命令: ${BOLD}$1${NC}"
    fi
}

# 打印分隔线
print_separator() {
    echo -e "${BLUE}----------------------------------------${NC}"
}

# 显示脚本标题
print_separator
echo -e "${GREEN}${BOLD}LVM 逻辑卷自动扩容脚本${NC}"
print_separator

# 检查必要的命令
log "检查系统环境..."
check_command vgdisplay
check_command lvdisplay
check_command lvextend
check_command resize2fs
log_success "系统环境检查完成"

# 获取所有卷组信息
log "获取卷组信息..."
# 创建关联数组存储卷组和对应的可用PE
declare -A VG_FREE_PE
while IFS= read -r line; do
    vg_name=$(echo "$line" | awk '{print $3}')
    free_pe=$(vgdisplay "$vg_name" | grep -w "Free" | awk '{print $5}' | tr -d ' ')
    
    # 只保存有可用空间的卷组
    if [[ "$free_pe" =~ ^[0-9]+$ ]] && [ "$free_pe" -gt 0 ]; then
        VG_FREE_PE["$vg_name"]=$free_pe
    fi
done < <(vgdisplay | grep "VG Name")

# 检查是否有可用的卷组
if [ ${#VG_FREE_PE[@]} -eq 0 ]; then
    handle_error "没有找到具有可用空间的卷组"
fi

# 如果有多个可用卷组，显示选择菜单
if [ ${#VG_FREE_PE[@]} -gt 1 ]; then
    log "检测到多个具有可用空间的卷组:"
    PS3="请选择要操作的卷组 (输入数字): "
    select vg_name in "${!VG_FREE_PE[@]}"; do
        if [ -n "$vg_name" ]; then
            break
        else
            echo "无效选择，请重试"
        fi
    done
else
    vg_name="${!VG_FREE_PE[@]}"
fi

FreePE="${VG_FREE_PE[$vg_name]}"
log_success "选择的卷组: ${BOLD}$vg_name${NC} (可用PE: ${BOLD}$FreePE${NC})"

# 获取选定卷组中的逻辑卷路径
log "获取逻辑卷路径..."
mapfile -t LV_PATHS < <(lvdisplay "$vg_name" | grep 'LV Path' | awk '{print $3}')

if [ ${#LV_PATHS[@]} -eq 0 ]; then
    handle_error "在卷组 $vg_name 中未找到逻辑卷"
fi

# 如果有多个逻辑卷，显示选择菜单
if [ ${#LV_PATHS[@]} -gt 1 ]; then
    log "检测到多个逻辑卷:"
    PS3="请选择要扩展的逻辑卷 (输入数字): "
    select LVPath in "${LV_PATHS[@]}"; do
        if [ -n "$LVPath" ]; then
            break
        else
            echo "无效选择，请重试"
        fi
    done
else
    LVPath="${LV_PATHS[0]}"
fi

log_success "逻辑卷路径: ${BOLD}$LVPath${NC}"

# 检查逻辑卷路径是否存在
if [ ! -e "$LVPath" ]; then
    handle_error "逻辑卷路径不存在: $LVPath"
fi

# 显示当前空间使用情况
print_separator
log "当前空间使用情况:"
if ! df -h "$LVPath" | tail -n 1 | awk '{printf "  已用空间: %s\n  可用空间: %s\n  使用率: %s\n", $3, $4, $5}'; then
    log_warning "无法获取当前空间使用情况"
fi
print_separator

# 扩展逻辑卷
log "开始扩展逻辑卷..."
if ! lvextend -l "+$FreePE" "$LVPath"; then
    handle_error "lvextend命令执行失败"
fi
log_success "逻辑卷扩展完成"

# 调整文件系统大小
log "调整文件系统大小..."
if ! resize2fs "$LVPath"; then
    handle_error "resize2fs命令执行失败"
fi
log_success "文件系统调整完成"

# 验证扩容结果
log "验证扩容结果..."
new_free_pe=$(vgdisplay "$vg_name" | grep -w "Free" | awk '{print $5}' | tr -d ' ')
if [ -z "$new_free_pe" ]; then
    handle_error "无法获取扩容后的PE数量"
fi

# 确保new_free_pe是数字
if ! [[ "$new_free_pe" =~ ^[0-9]+$ ]]; then
    handle_error "获取到的PE数量不是有效数字: $new_free_pe"
fi

if [ "$new_free_pe" -ne 0 ]; then
    handle_error "扩容失败：仍有未使用的PE ($new_free_pe)"
fi

log_success "扩容成功完成"

# 显示最终结果
print_separator
log "扩容后空间使用情况:"
if ! df -h "$LVPath" | tail -n 1 | awk '{printf "  已用空间: %s\n  可用空间: %s\n  使用率: %s\n", $3, $4, $5}'; then
    log_warning "无法获取扩容后空间使用情况"
fi
echo -e "\n逻辑卷大小:"
lvdisplay "$LVPath" | grep 'LV Size' | sed 's/^/  /'
print_separator

# 脚本完成
echo -e "${GREEN}${BOLD}扩容操作已成功完成！${NC}"
print_separator
