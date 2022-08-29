#!/bin/bash
#定义前一天时间变量
THEDAY=`date -d yesterday +%F`
#日志文件存储路径
LOGDIR="/home/logs"
#日志文件前缀名称
LOGPRE="chem.log"
cd ${LOGDIR} && tar -czvf ${LOGPRE}.${THEDAY}.tar.gz ${LOGPRE}.${THEDAY} && rm -f ${LOGPRE}.${THEDAY}
