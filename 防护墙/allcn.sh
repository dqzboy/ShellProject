#!/bin/bash
#===============================================================================
#
#          FILE: allcn.sh
# 
#         USAGE: ./allcn.sh
#   DESCRIPTION: 通过iptables限制访问网段，只允许大陆、港澳台IP可以访问
# 
#  ORGANIZATION: dqzboy.com
#===============================================================================
mmode=$1

if [ "$mmode" != "stop" ] ;then
#下面语句可以单独执行，不需要每次执行都获取网段表
iptables -F
wget -q --timeout=60 -O- 'http://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest' | awk -F\| '/CN\|ipv4/ || /HK\|ipv4/ || /TW\|ipv4/ ||/MO\|ipv4/ { printf("%s/%d\n", $4, 32-log($5)/log(2)) }' > /root/china_ssr.txt
CNIP="/root/china_ssr.txt"
fi

gen_iplist() {
        cat <<-EOF
                $(cat ${CNIP:=/dev/null} 2>/dev/null)
EOF
}

flush_r() {
iptables  -F ALLCNRULE 2>/dev/null
iptables -D INPUT -p tcp -j ALLCNRULE 2>/dev/null
iptables  -X ALLCNRULE 2>/dev/null
ipset -X allcn 2>/dev/null
}

mstart() {
ipset create allcn hash:net 2>/dev/null
ipset -! -R <<-EOF
$(gen_iplist | sed -e "s/^/add allcn /")
EOF

iptables -N ALLCNRULE
iptables -I INPUT -p tcp -j ALLCNRULE
iptables -A ALLCNRULE -s 127.0.0.0/8 -j RETURN
iptables -A ALLCNRULE -s 169.254.0.0/16 -j RETURN
iptables -A ALLCNRULE -s 224.0.0.0/4 -j RETURN
iptables -A ALLCNRULE -s 255.255.255.255 -j RETURN
#可在此增加你的公网网段，避免调试ipset时出现自己无法访问的情况

iptables -A ALLCNRULE -m set --match-set allcn  src -j RETURN
iptables -A ALLCNRULE -p tcp -j DROP


}

if [ "$mmode" == "stop" ] ;then
flush_r
exit 0
fi

flush_r
sleep 1
mstart
