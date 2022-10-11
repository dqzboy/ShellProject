#!/bin/bash
#===============================================================================
#
#          FILE: firewalld_Closure.sh
# 
#         USAGE: ./firewalld_Closure.sh prot
#   DESCRIPTION: 通过iptables限制访问网段，只允许大陆、港澳台IP可以访问
# 
#  ORGANIZATION: dqzboy.com
#===============================================================================
PORT="$1"
White_list=`firewall-cmd --query-port=${PORT}/tcp`
fireState=`firewall-cmd --state`
if [[ $fireState == "running" ]];then
    echo "防火墙开启>>>>>>>>"
    if [ "$PORT" != '' ] && [ "$PORT" -le "65535" ];then
        if [[ $White_list == yes ]];then
            echo "端口已在放通名单中,接下来关闭端口"
            firewall-cmd --permanent --zone=public --remove-port=${PORT}/tcp
            firewall-cmd --reload
        else
            echo "名单中无此端口号,无需进行关闭"
        fi
    else
        echo "参数无效，本次流程结束"
        exit 1
    fi
else
    echo "防火墙关闭>>>>>>>>"
    exit 2
fi
