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

# 获取3天前的日期
timestamp=$(date -d "3 days ago" +%Y%m%d)

# 遍历日志文件
for file in $log_dir/boot.log-* $log_dir/btmp-* $log_dir/cron-* $log_dir/hawkey.log-* $log_dir/maillog-* $log_dir/messages-* $log_dir/secure-* $log_dir/spooler-*
do
    # 检查文件是否符合条件
    if [[ -f $file ]]
    then
        # 提取文件名的开头部分
        filename=$(basename $file)
        prefix=${filename%%-*}

        # 检查文件名开头是否匹配指定的前缀
        if [[ $prefix =~ ^(boot\.log|btmp|cron|hawkey\.log|maillog|messages|secure|spooler)$ ]]
        then
            # 提取文件名的日期部分
            file_date=${filename#*-}

            # 检查文件是否是3天前的文件
            if [[ $file_date -lt $timestamp ]]
            then
                # 删除文件
                rm -f $file
            fi
        fi
    fi
done
