#!/usr/bin/env bash
#===============================================================================
#
#          FILE: get_disk usage_alert.sh
# 
#         USAGE: ./get_disk usage_alert.sh [File_system|Mounted_on]
#                ./get_disk usage_alert.sh [-i|-u]
#   DESCRIPTION: open_mail_alert字段设置为1时：
#				 根据Filesystem（例如：/dev/sda1）或 Mounted on（例如：/data）获取磁盘使用率
#				 并输出Disk usage（例如：15%）；如果没有输入参数则输出全部Disk usage，Mounted_on信息
#
#				 open_mail_alert字段设置为0时：
#                监控monitor_mount_dir字段中定义的监控分区，添加到crontab中，当分区超过使用率时，发出邮件告警
#				 (一般使用QQ邮箱需要使用ssl方式发送邮件，163邮件使用普通方式就OK)
# 
#  ORGANIZATION: dqzboy.com
#===============================================================================

ok(){
    echo "$(date +%F\ %T)|$$|$BASH_LINENO|info|job success: $*" 
    exit 0
}

die(){
    echo "$(date +%F\ %T)|$$|$BASH_LINENO|error|job fail: $*" >&2
    exit 1
}

usage() { 
    cat <<_OO_
USAGE:
    $0 [File_system|Mounted_on]

_OO_
}
#邮件告警功能字段定义
open_mail_alert=0 # 0代表关闭邮件告警，开启查询磁盘使用率模式；1代表开启邮件告警，关闭查询磁盘使用率模式；默认为关闭状态，以下邮件信息配置好后方可打开，否则会导致邮件告警失败
mail_from="xxx@qq.com" #定义邮件告警发件人
mail_to="111111@qq.com,222222@qq.com,3333333@126.com" #定义邮件告警收件人，多个告警收件人用逗号分隔（,）
smtp_addr_port="smtp.qq.com:465" #定义smtp地址和端口，如果不指定端口，默认为25
mail_user="xxx@qq.com" #定义发件人用户
mail_password="xxx" #定义发件人密码
ssl_enable=1 #1代表发送告警邮件使用SSL协议，0代表使用普通邮件协议，默认设置为0
monitor_mount_dir="all" #定义需告警的挂载目录，多个挂载目录用竖线分隔（|），如果要监控服务器上所有磁盘需要输入 ALL
alert_limit=60 #设置告警阈值百分比，如果磁盘空间使用等于或超过设置阈值则发出邮件告警
monitoring_interval=5 #设置监控告警间隔，单位为分钟


#获取磁盘使用率函数
disk_usage_info=""
get_disk_usage(){
    local filesystem_or_mount="$1"
	if [[ -z "$filesystem_or_mount" ]];then
		disk_usage_info=$(df|awk 'NR>1{print $(NF-1),$NF}'|sort -r)
		echo "$disk_usage_info"
	else
		local tmp_filesystem_or_mount=${filesystem_or_mount/\/dev\//}
		local tmp_mount=$(df $tmp_filesystem_or_mount 2>/dev/null|awk 'NR>1{print $(NF-1)}')
		if [[ -z "$tmp_mount" ]];then
			df /dev/$tmp_filesystem_or_mount 2>/dev/null|awk 'NR>1{print $(NF-1)}'
		else
			echo "$tmp_mount"
		fi
	fi
}


if [[ $open_mail_alert -eq 0 ]];then
    #获取磁盘使用率
    disk_usage_result=$( get_disk_usage "$1" )
    if [[ -z "$disk_usage_result" ]];then
    	die "Get disk usage fail,please confirm the $1 file_system or mount_on existence"
    else
    	ok "$disk_usage_result"
    fi
elif [[ $open_mail_alert -eq 1 ]];then
	#安装定期监控
	if [[ $1 == "-i" ]];then
        #如果开启邮件告警功能执行者必须是root权限
	    if ! id | grep -Eq '^uid=0\('; then
	    	die "You must use the root user to open the mail alert"
	    fi
	    
	    #判断mail程序是否存在
	    mail_bin=$( which mailx )
	    if [[ -z "$mail_bin" ]];then
	    	die "You must install the mailx package"
	    fi
		
		#判断smtp服务器是否可以ping通
	    smtp_addr=$( echo "$smtp_addr_port"|awk -F ":" '{print $1}' )
	    ping -c 1 $smtp_addr 1>/dev/null 2>&1
	    if [[ $? -ne 0 ]];then
	    	die "Please check the SMTP address $smtp_addr connectivity"
	    fi
		
		#如果开启了SSL协议
		if [[ $ssl_enable -eq 1 ]];then
			ssl_dir=~/.certs
			smtp_addr_port_ssl="smtps://$smtp_addr_port" #添加ssl协议头
			
			#判断openssl程序是否存在
			ssl_bin=$( which openssl )
			if [[ -z "$ssl_bin" ]];then
				die "You must install the openssl package"
			fi
			
			#生成smtps所需证书
			[[ -d $ssl_dir ]] || mkdir -p $ssl_dir
			[[ -s $$ssl_dir/smtps.crt ]] && rm -f $ssl_dir/smtps.crt
			echo -n | openssl s_client -connect "$smtp_addr_port" 2>/dev/null| sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > $ssl_dir/smtps.crt
			if [[ ! -s $ssl_dir/smtps.crt ]];then
				die "Failed to generate certificate $ssl_dir/smtps.crt"
			fi	
			certutil -A -n "GeoTrust SSL CA" -t "C,," -d ~/.certs -i $ssl_dir/smtps.crt 1>/dev/null 2>&1
			if [[ $? -ne 0 ]];then
				die "Failed to certutil1 certificate $ssl_dir/smtps.crt"
			fi
			certutil -A -n "GeoTrust Global CA" -t "C,," -d ~/.certs -i $ssl_dir/smtps.crt 1>/dev/null 2>&1
			if [[ $? -ne 0 ]];then
				die "Failed to certutil2 certificate $ssl_dir/smtps.crt"
			fi
			certutil -L -d $ssl_dir 1>/dev/null 2>&1
			if [[ $? -ne 0 ]];then
				die "Failed to certutil3 certificate $ssl_dir/smtps.crt"
			fi
		fi
		
		#添加crontab
		cron_file='/var/spool/cron/root'
		sciprt_name=$(cd "$(dirname "$0")";pwd)/$(basename "$0")
		chmod +x $sciprt_name
		echo "*/${monitoring_interval} * * * * $sciprt_name 1>/dev/null 2>&1" >>$cron_file
		service crond reload 1>/dev/null 2>&1
		ok "Install mail monitoring success"
    fi
	
	
	#卸载定期监控
	if [[ $1 == "-u" ]];then
		cron_file='/var/spool/cron/root'
		sciprt_name=$(basename "$0")
		/bin/sed -i '/'${sciprt_name}'/d' $cron_file
		service crond reload 1>/dev/null 2>&1
		ok "Uninstall mail monitoring success"
    fi
	
	
	#执行监控逻辑
    #Get IP ADDRESS	
    ip=$( /sbin/ifconfig|awk -F ":| +" '{if($0 ~ /inet addr:/ && $4 !~ /127\.0\./){print $4}}' )
	
	#如果monitor_mount_dir值为ALL，则监控服务器全部分区
	capital_all=$( echo "$monitor_mount_dir"|tr [a-z] [A-Z] )
	if [[ $capital_all == "ALL" ]];then
		monitor_mount_dir_tmp=$( df|awk 'BEGIN{monitor_list=""}NR>1{monitor_list=monitor_list"|"$NF}END{print monitor_list}' )
		monitor_mount_dir=${monitor_mount_dir_tmp/\|/}
	fi
	
	#定义ssl目录
	ssl_dir=~/.certs
	smtp_addr_port_ssl="smtps://$smtp_addr_port" #添加ssl协议头

	if [[ $ssl_enable -eq 1 ]];then	
		#判断磁盘使用率超过设定阈值，邮件告警通知
		for mount_dir in ${monitor_mount_dir//|/ }
		do
			disk_usage_result=$( get_disk_usage "$mount_dir" )
			if [[ ${disk_usage_result/\%/} -ge $alert_limit ]];then
				echo "Host name:${HOSTNAME} 

IP:$ip 

Disk $mount_dir usage $disk_usage_result exceeded limited ${alert_limit}%"|mailx -s "Host name:${HOSTNAME} Disk $mount_dir usage $disk_usage_result exceeded limited ${alert_limit}%" -S ssl-verify=ignore -S smtp-auth=login -S smtp="$smtp_addr_port_ssl" -S from="${mail_from}(Disk Usage Alert)" -S smtp-auth-user="$mail_user" -S smtp-auth-password="$mail_password" -S nss-config-dir="$ssl_dir" $mail_to 2>/dev/null
                sleep 3
			fi
		done
    else
		#判断磁盘使用率超过设定阈值，邮件告警通知(not ssl)
		for mount_dir in ${monitor_mount_dir//|/ }
		do
			disk_usage_result=$( get_disk_usage "$mount_dir" )
			if [[ ${disk_usage_result/\%/} -ge $alert_limit ]];then
				echo "Host name:${HOSTNAME} 

IP:$ip 

Disk $mount_dir usage $disk_usage_result exceeded limited ${alert_limit}%"|mailx -s "Host name:${HOSTNAME} Disk $mount_dir usage $disk_usage_result exceeded limited ${alert_limit}%" -S smtp-auth=login -S smtp="$smtp_addr_port" -S from="${mail_from}(Disk Usage Alert)" -S smtp-auth-user="$mail_user" -S smtp-auth-password="$mail_password" $mail_to 2>/dev/null
                sleep 3
			fi
		done
	fi
	
else
	die "open_mail_alert variable must 0 or 1"
fi
