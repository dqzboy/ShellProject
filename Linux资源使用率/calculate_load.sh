#!/usr/bin/env bash
#===============================================================================
#
#          FILE: calculate_load.sh
# 
#         USAGE: ./calculate_load.sh 
# 
#   DESCRIPTION: 计算当前服务器1分钟、5分钟、15分钟的负载
# 
#  ORGANIZATION: dqzboy.com
#===============================================================================

# 获取CPU核心数量
cpu_cores=$(grep -c ^processor /proc/cpuinfo)

# 使用uptime命令获取系统负载平均值
load_averages=$(uptime | awk -F'average:' '{print $2}' | tr -d ',')

# 提取1分钟、5分钟和15分钟的负载值
load_1min=$(echo "$load_averages" | awk '{print $1}')
load_5min=$(echo "$load_averages" | awk '{print $2}')
load_15min=$(echo "$load_averages" | awk '{print $3}')

# 计算load average百分比
load_1min_percentage=$(echo "scale=2; $load_1min / $cpu_cores * 100" | bc)
load_5min_percentage=$(echo "scale=2; $load_5min / $cpu_cores * 100" | bc)
load_15min_percentage=$(echo "scale=2; $load_15min / $cpu_cores * 100" | bc)

calculate_percentage() {
    local load_value=$1
    local percentage=$(echo "scale=2; $load_value / $cpu_cores * 100" | bc)

    # 小于0.01的情况显示为具体值，否则显示两位小数
    if (( $(echo "$percentage < 0.01" | bc -l) )); then
        echo "$percentage"
    else
        echo "$(printf "%.2f" $percentage)"
    fi
}

# 打印结果
echo "CPU Cores: $cpu_cores"
echo "Load Average (1min): $load_1min, Load Percentage: $(calculate_percentage $load_1min)%"
echo "Load Average (5min): $load_5min, Load Percentage: $(calculate_percentage $load_5min)%"
echo "Load Average (15min): $load_15min, Load Percentage: $(calculate_percentage $load_15min)%"
