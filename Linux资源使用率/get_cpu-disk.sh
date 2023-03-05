#!/usr/bin/env bash
#===============================================================================
#
#          FILE: get_cpu-disk.sh
# 
#         USAGE: ./get_cpu-disk.sh
#         
#       DESCRIPTION: 每隔 5 秒检测一次 CPU、内存和磁盘的占用率，并将检测结果输出到终端。可以根据需要修改脚本中的检测间隔和检测内容
# 
#       ORGANIZATION: dqzboy.com
#===============================================================================

while true
do
  # 获取 CPU 占用率
  cpu_load=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')
  cpu_load=${cpu_load/.*}

  # 获取内存占用率
  mem_used=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
  mem_used=${mem_used/.*}

  # 获取磁盘占用率
  disk_used=$(df / | awk '/\// {print $5}' | sed 's/%//g')

  # 打印资源使用情况
  echo "CPU 占用率：$cpu_load%"
  echo "内存占用率：$mem_used%"
  echo "磁盘占用率：$disk_used%"

  # 等待 5 秒
  sleep 5
done
