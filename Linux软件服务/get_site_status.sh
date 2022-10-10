#!/usr/bin/env bash
#===============================================================================
#
#          FILE: get_site_status.sh
# 
#         USAGE: ./get_site_status.sh <url>
# 
#   DESCRIPTION: 使用curl检测url，输出相关指标
# 
#  ORGANIZATION: dqzboy.com
#===============================================================================

if [[ -z "$1" ]]; then
    echo "$0 <url>"
    exit 1
fi

echo "访问$1的统计数据："
curl -L -w '
HTTP返回码:\t%{http_code}
返回内容大小:\t%{size_download}
重定向次数:\t%{num_redirects}

域名解析时长:\t%{time_namelookup}
建立链接时长:\t%{time_connect}
开始传输时长:\t%{time_starttransfer}
总时长:\t%{time_total}

' -o /dev/null -s "$1"
