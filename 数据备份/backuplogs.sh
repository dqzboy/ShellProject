#!/bin/bash
#===============================================================================
#
#          FILE: backuplogs.sh
# 
#         USAGE: ./backuplogs.sh
#   DESCRIPTION: 对前一天的日志进行打包备份
# 
#  ORGANIZATION: dqzboy.com
#===============================================================================

#定义前一天时间变量
THEDAY=`date -d yesterday +%F`
#日志文件存储路径
LOGDIR="/home/logs"
#日志文件前缀名称
LOGPRE="chem.log"
cd ${LOGDIR} && tar -czvf ${LOGPRE}.${THEDAY}.tar.gz ${LOGPRE}.${THEDAY} && rm -f ${LOGPRE}.${THEDAY}
