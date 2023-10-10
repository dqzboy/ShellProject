#!/usr/bin/env bash
#===============================================================================
#
#          FILE: cleanup_logs.sh
# 
#         USAGE: ./cleanup_logs.sh 
# 
#   DESCRIPTION: 理3天前位于 /var/log 目录下以 boot.log-, btmp-, cron-, hawkey.log-, maillog-, messages-, secure-, spooler- 开头的文件
# 
#  ORGANIZATION: dqzboy.com
#       CREATED: 2022
#===============================================================================

SETCOLOR_SKYBLUE="echo -en \\E[1;36m"
SETCOLOR_SUCCESS="echo -en \\E[1;32m"
SETCOLOR_NORMAL="echo  -en \\E[0;39m"

echo
cat << EOF
██████╗  ██████╗ ███████╗██████╗  ██████╗ ██╗   ██╗            ██████╗ ██████╗ ███╗   ███╗
██╔══██╗██╔═══██╗╚══███╔╝██╔══██╗██╔═══██╗╚██╗ ██╔╝           ██╔════╝██╔═══██╗████╗ ████║
██║  ██║██║   ██║  ███╔╝ ██████╔╝██║   ██║ ╚████╔╝            ██║     ██║   ██║██╔████╔██║
██║  ██║██║▄▄ ██║ ███╔╝  ██╔══██╗██║   ██║  ╚██╔╝             ██║     ██║   ██║██║╚██╔╝██║
██████╔╝╚██████╔╝███████╗██████╔╝╚██████╔╝   ██║       ██╗    ╚██████╗╚██████╔╝██║ ╚═╝ ██║
╚═════╝  ╚══▀▀═╝ ╚══════╝╚═════╝  ╚═════╝    ╚═╝       ╚═╝     ╚═════╝ ╚═════╝ ╚═╝     ╚═╝
                                                                                          
EOF

# 指定日志文件所在目录
log_dir="/var/log"

# 定义日志前缀列表
log_prefixes=("boot.log" "btmp" "cron" "hawkey.log" "maillog" "messages" "secure" "spooler")

# 获取3天前的日期
timestamp=$(date -d "3 days ago" +%Y%m%d)

# 遍历日志前缀
for prefix in "${log_prefixes[@]}"
do
    # 生成日志文件路径
    file_path="$log_dir/$prefix-"

    # 遍历日志文件
    for file in $file_path*
    do
        # 检查文件是否符合条件
        if [[ -f $file ]]
        then
            # 提取文件名的日期部分
            filename=$(basename $file)
            file_date=${filename#*-}

            # 检查文件是否是3天前的文件
            if [[ $file_date -lt $timestamp ]]
            then
                # 删除文件
                rm -f $file
            fi
        fi
    done
done
