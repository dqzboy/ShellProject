#!/usr/bin/env bash
#===============================================================================
#
#          FILE: get_proc_stat.sh
# 
#         USAGE: ./get_proc_stat.sh [name|pid|arg] [value]
# 
#   DESCRIPTION: 根据进程名或PID或进程命令行参数查询进程，并输出相关进程信息
# 
#  ORGANIZATION: dqzboy.com
#===============================================================================

set -o nounset                              # Treat unset variables as an error

ok () {
    echo "$(date +%F\ %T)|$$|$BASH_LINENO|info|job success: $*" 
    exit 0
}

die () {
    echo "$(date +%F\ %T)|$$|$BASH_LINENO|error|job fail: $*" >&2
    exit 1
}

usage() { 
    cat <<_OO_
USAGE:
    get_proc_stat.sh [name|pid|arg] [value]

_OO_
    exit 1
}

# 通过/proc/下获取文件句柄和进程工作目录
get_pid_stat_proc() {
    local pids="$1"

    {
    shopt -s nullglob
    echo "CWD FH"
    for pid in ${pids/,/ /}; do
	cwd=$(readlink -f "/proc/$pid/cwd")
	fds=(/proc/$pid/fd/*)
	fd_cnt=${#fds[@]}
	[[ -z "$cwd" ]] && cwd="NULL"
	(( fd_cnt == 0 )) && fd_cnt="NOACCESS"
	echo "$cwd $fd_cnt"
    done
    } | column -t 
}

# 获取指定PID的所有子进程PID
get_chd_pid() {
    local chd_pids=$(pgrep -P "$1" | xargs)
    for cpid in $chd_pids; do
	echo "$cpid"
	get_chd_pid "$cpid"
    done
}

# 输出进程的所有子进程数量
get_pid_cpid_cnt() {
    local pids="$1"

    {
    shopt -s nullglob
    echo "CHD"
    for pid in ${pids/,/ }; do
	chd=$(get_chd_pid "$pid" | wc -l)
	echo "$chd"
    done
    } | column -t
}


# 汇总输出
get_pid_stat() {
    local pids="$1"

    if [[ -z "$pids" ]]; then
	die "no such process."
    fi

    # sort pids
    pids=$(echo "$pids" | sed s'/,/\n/g'  | sort -n | xargs | sed 's/ /,/g')

    ps_output=$(ps -p "$pids" -o pid,comm,user,pcpu,rss,stat,lstart)
    cwd_output=$(get_pid_stat_proc "$pids") 
    cpid_output=$(get_pid_cpid_cnt "$pids")
    paste <(echo "$ps_output") <(echo "$cwd_output") <(echo "$cpid_output")
}

if [[ $# -eq 2 ]]; then
    case $1 in 
	name)	pids=$(pgrep -d, -x "$2") ;;
	arg)	pids=$(pgrep -d, -f "$2") ;;
	pid) 	pids="$2" ;;
	*) 	usage ;;
    esac

    get_pid_stat "$pids"
else
    usage
fi
