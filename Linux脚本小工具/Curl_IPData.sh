#!/usr/bin/env bash
#===============================================================================
#
#          FILE: Curl_IPData.sh
# 
#         USAGE: ./Curl_IPData.sh 
# 
#   DESCRIPTION: 截取Nginx日志IP地址并分析IP数据
# 
#  ORGANIZATION: dqzboy.com
#       CREATED: 2020
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

# 定义时间
TIME=$(date "+%Y-%m-%d")

# 定义源日志文件
SOURCE_FILE="/var/log/nginx/access.log"

# 定义执行日志路径
RESULT_LOG="${PWD}/${TIME}_result_log.txt"
echo > ${RESULT_LOG}

# 定义读取的文件路径
READ_FILE="/root/clientip.txt"
# 过滤出IPV4 IP并去除重复IP
cat ${SOURCE_FILE} | grep -o '\([0-9]\{1,3\}\.\)\{3\}[0-9]\{1,3\}'|sort -d | uniq > ${READ_FILE}

# 循环执行指令
for IP in `cat ${READ_FILE}`
do
${SETCOLOR_SKYBLUE} && echo "=====================================START====================================="  | tee -a ${RESULT_LOG}
${SETCOLOR_NORMAL}
    #curl cip.cc/${IP} | tee -a result_log.txt
    curl -s --max-time 5 --url http://www.cip.cc/${IP}  | tee -a ${RESULT_LOG}
    sleep 3
${SETCOLOR_SUCCESS} && echo "====================================SUCCESS===================================="  | tee -a ${RESULT_LOG}
${SETCOLOR_NORMAL} && echo | tee -a ${RESULT_LOG}
${SETCOLOR_NORMAL} && echo | tee -a ${RESULT_LOG}
${SETCOLOR_NORMAL} && echo | tee -a ${RESULT_LOG}
done
# 清除颜色
${SETCOLOR_NORMAL}
