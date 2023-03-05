#!/bin/bash
#===============================================================================
#
#          FILE: unlawful.sh
# 
#         USAGE: ./unlawful.sh
#   DESCRIPTION: 通过 iptables 配置防火墙规则，限制非法连接，保护系统安全
# 
#  ORGANIZATION: dqzboy.com
#===============================================================================

# 允许所有本地回环连接
iptables -A INPUT -i lo -j ACCEPT

# 允许已经建立的、相关的连接通过
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# 允许SSH连接
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# 允许HTTP和HTTPS连接
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# 允许Ping连接
iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT

# 阻止所有其他连接
iptables -A INPUT -j DROP

# 保存防火墙规则
iptables-save > /etc/sysconfig/iptables

# 设置防火墙开机启动
systemctl enable iptables.service

# 启动防火墙
systemctl start iptables.service

# 显示防火墙状态
systemctl status iptables.service
