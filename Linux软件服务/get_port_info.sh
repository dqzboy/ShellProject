#!/usr/bin/env bash
#===============================================================================
#
#          FILE: get_port_info.sh
# 
#         USAGE: ./get_svr_info.sh [-h] [-i ip] -p <port>
# 
#   DESCRIPTION: 获取指定服务端口的统计信息
# 
#  ORGANIZATION: dqzboy.com
#===============================================================================

set -o nounset                              # Treat unset variables as an error

export LC_ALL=C
export LANG=C

usage() {
    cat <<EOF
    Usage: $0 [-h] [-i ip] -p <port>
EOF
    exit 1
}

precheck() {
    if ! which ss &> /dev/null; then
        echo "ss not found, try install iproute2 package first"        
        exit 1
    fi

    if [[ $( id -u ) != 0 ]]; then
        echo "$0 should run under root"
        exit 1
    fi
}

get_service_name(){
    local port=$1
    local proto=$2

    local service=$( grep -E '^[a-z]' /etc/services  | 
        awk -vport=$port -v proto=$proto '{ if ( $2 == port"/"proto ) { print $1; exit 0 } } ' 
    )

    [[ -z $service ]] && services="N/A"
    echo $service
}

################################################################################

port=
proto=tcp

while getopts "i:p:h" arg; do
    case $arg in
        i)
            ip=$OPTARG
            ;;
        p)
            port=$OPTARG
            ;;
        h|?)
            usage >&2
            exit 1
            ;;
    esac
done


if [[ -z $port ]]; then
    usage
fi

precheck

tmpf=$( mktemp )
ss -lant 2>/dev/null | sed -e 's/::/*/' -e 's/:/\t/g' > "$tmpf"

listen_ip=$( awk -vport=$port '{ if ($1 == "LISTEN" && $5 == port) { print $4; } }' "$tmpf" | sort -u | xargs | tr ' ' ',' )
if [[ -z $listen_ip ]]; then
    echo -e "Listen ip:\tN/A"
    exit 1
fi

echo -e "Listen ip:\t$listen_ip"
echo -e "Protocol:\ttcp"
echo -e "Port:\t$port"
echo -e "Service:\t$( get_service_name $port $proto)"
echo -e "Connections:"

awk -vport=$port '{ 
        if ( $1 != "LISTEN" && $5 == port ) { stat[$1]++ } 
    } 
    END { 
        for (s in stat) { print "\t"s":\t"stat[s] }  
    } ' "$tmpf"

/bin/rm "$tmpf"
