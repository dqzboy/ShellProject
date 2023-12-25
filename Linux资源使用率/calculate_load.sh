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

# 获取top命令的输出
top_output=$(top -n 1)

# 获取top命令的load average值，并去掉逗号
load_1min=$(echo "$top_output" | grep -oP 'load average: \K[0-9.]+(?=,)')
load_5min=$(echo "$top_output" | grep -oP 'load average: [0-9.]+, \K[0-9.]+(?=,)')
load_15min=$(echo "$top_output" | grep -oP 'load average: [0-9.]+, [0-9.]+, \K[0-9.]+')

# 计算load average百分比
load_1min_percentage=$(echo "scale=2; $load_1min / $cpu_cores * 100" | bc)
load_5min_percentage=$(echo "scale=2; $load_5min / $cpu_cores * 100" | bc)
load_15min_percentage=$(echo "scale=2; $load_15min / $cpu_cores * 100" | bc)

# 打印结果
echo "CPU Cores: $cpu_cores"
echo "Load Average (1min): $load_1min, Load Percentage: $load_1min_percentage%"
echo "Load Average (5min): $load_5min, Load Percentage: $load_5min_percentage%"
echo "Load Average (15min): $load_15min, Load Percentage: $load_15min_percentage%"
