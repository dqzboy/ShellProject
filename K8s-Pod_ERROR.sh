#!/bin/bash
#注意这里要声明环境变量，不然不识别kubectl命令
PATH=/etc:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
nameSpace="default"
pod=$(kubectl get pod -n default |awk '{print $1}');
for i in $pod;
do
	if [ $i = 'NAME' ]
	then
		continue
	fi
podname=$i;
appname=`echo $i|awk -F '-' '{print $1 "_" $2}'`;

#导出今天每个Pod服务日志中ERROR的数量
errorAll=`echo "$podname------>" && kubectl logs --since=24h $podname -n ${nameSpace}| grep "ERROR" | wc -l`
echo ${errorAll} >> /home/pod_error.txt
done;
#按照每个Pod的ERROR数量进行排序
sort -t '>' -k 2 -nr /home/pod_error.txt > /home/PodError.txt
#通过邮件发送给指定人员;生产环境请修改邮件正文内容
echo -e """
---------------------------------------------------
|  统计时间 | `date +"%Y/%m/%d %H:%M"`                   
|--------------------------------------------------
|  统计环境 | 测试K8s                       
|--------------------------------------------------
|  名称空间 | default                     
|--------------------------------------------------
|  推送信息 | Pod ERROR统计，请查看附件内容 
---------------------------------------------------
""" | mail -s "TEST-K8s Pod Logs ERROR" -a /home/PodError.txt dingqinzheng@xxx.com
#删除txt文件
sleep 3
rm -f /home/pod_error.txt
