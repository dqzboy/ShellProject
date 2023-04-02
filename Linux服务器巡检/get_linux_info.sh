#!/usr/bin/env bash
#===============================================================================
#
#          FILE: get_linux_info.sh
# 
#         USAGE: ./get_linux_info.sh 
# 
#   DESCRIPTION: 获取当前服务器的cpu/mem等信息
# 
#  ORGANIZATION: dqzboy.com
#       CREATED: 2019
#===============================================================================

set -o nounset                              # Treat unset variables as an error

echo
cat << EOF
██████╗  ██████╗ ███████╗██████╗  ██████╗ ██╗   ██╗            ██████╗ ██████╗ ███╗   ███╗
██╔══██╗██╔═══██╗╚══███╔╝██╔══██╗██╔═══██╗╚██╗ ██╔╝           ██╔════╝██╔═══██╗████╗ ████║
██║  ██║██║   ██║  ███╔╝ ██████╔╝██║   ██║ ╚████╔╝            ██║     ██║   ██║██╔████╔██║
██║  ██║██║▄▄ ██║ ███╔╝  ██╔══██╗██║   ██║  ╚██╔╝             ██║     ██║   ██║██║╚██╔╝██║
██████╔╝╚██████╔╝███████╗██████╔╝╚██████╔╝   ██║       ██╗    ╚██████╗╚██████╔╝██║ ╚═╝ ██║
╚═════╝  ╚══▀▀═╝ ╚══════╝╚═════╝  ╚═════╝    ╚═╝       ╚═╝     ╚═════╝ ╚═════╝ ╚═╝     ╚═╝
                                                                                          
EOF

## 预检，判断执行权限
prececk() {
    if [[ $( id -u ) != 0 ]]; then
        echo "$0 should run as root" 2>&1
        exit 1
    fi
}


## CPU INFO
get_cpu_info(){
    echo  "CPU:"
    {
        grep -m1 -E '^model name' /proc/cpuinfo 
        grep -m1 -E '^cpu MHz'    /proc/cpuinfo 
        grep -m1 -E '^cache size' /proc/cpuinfo 
    } |
        sed -r "s/\s+:\s+/:\t/" | 
        sed "s/^/\t/"

    local processor_cnt=$( grep -c processor /proc/cpuinfo )
    echo -e "\tcores cnt:\t$processor_cnt"

    if  lscpu 2> /dev/null | grep -Eq '^Thread\(s\) per core:[[:blank:]]+([2-9]|([0-9]{2,}))'; then
        echo -e "\thyper-threading: on"
    fi

    echo
}

# MEM INFO
get_mem_info(){
    echo "MEM:"
    free -m | grep -E '^(Mem|Swap)' | 
        awk '{ print $1, $2 }' | 
        sed -r -e 's/[[:blank:]]/\t/' -e 's/^/\t/' -e "s/$/ MB/"
    echo
}

## DISK INFO
get_disk_info(){
    echo "DISK:"
    df -h | grep -E '^/dev/' | awk '{ print "\t"$1":\t" $2 }'
    echo
}

## OS INFO
get_os_info(){
    echo "OS:"
    if which lsb_release &> /dev/null; then
        echo -e "\t$( lsb_release -d  )"
    elif ls /etc/*-release &> /dev/null &> /dev/null; then
        echo -e "\tDescription:\t$(cat /etc/*-release | head -n1)"
    else
        echo -e "\tDescription:\tN/A"
    fi

    echo -e "\tKernel Version:\t$( uname -r )"
    # procps 3.3.9
    #echo -e "\tStarted Since:\t$( uptime -s )"

    local uptime_sec=$( awk -F. '{ print $1 }' /proc/uptime )
    local current_sec=$( date +%s )
    local uptime_since=$((  current_sec - uptime_sec ))
    echo -e "\tStarted Since:\t$( date '+%F %T' -d +@$uptime_since )"

    ## 内核是否支持加载模块
    local module_loadable
    if [[ -e /proc/modules ]]; then
        module_loadable=Yes
    else
        module_loadable=No
    fi
    echo -e "\tModule Loadable:\t$module_loadable"

    ## 是否配置iptables规则
    local iptables_ouput_cnt=$( iptables -nvL 2> /dev/null | wc -l )
    if (( iptables_ouput_cnt <= 8 )); then
        echo -e "\tIptables Rules:\tOff"
    else
        echo -e "\tIptables Rules:\tOn"
    fi
}

################################################################################
prececk

get_cpu_info
get_mem_info
get_disk_info
get_os_info
