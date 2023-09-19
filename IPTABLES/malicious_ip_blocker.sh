#!/usr/bin/env bash
#===============================================================================
#
#          FILE: malicious_ip_blocker.sh
# 
#         USAGE: ./malicious_ip_blocker.sh
#   DESCRIPTION: lastb获取登入失败的IP，调用 iptables 限制恶意尝试登入的IP
# 
#  ORGANIZATION: dqzboy.com
#===============================================================================

iptables=$(command -v iptables)
iptables_save=$(command -v iptables-save)

# 获取登录失败的IP地址（仅提取有效的IP地址）
MALICIOUS_IPS=$(lastb -i | awk '$3 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {print $3}' | sort | uniq)

# 文件保存查询结果
OUTPUT_FILE="malicious_ips.txt"

# 之前已被拉黑的IP地址列表
BLACKLISTED_IPS="blacklisted_ips.txt"

# 从之前已拉黑的IP文件中读取
if [ -f "$BLACKLISTED_IPS" ]; then
    PREVIOUSLY_BLACKLISTED_IPS=$(cat "$BLACKLISTED_IPS")
else
    PREVIOUSLY_BLACKLISTED_IPS=""
fi

# 清空文件内容
> "$OUTPUT_FILE"

# 遍历恶意IP地址列表，添加防火墙规则并查询IP归属地
for ip in $MALICIOUS_IPS; do
    # 如果IP已经被拉黑，跳过
    if echo "$PREVIOUSLY_BLACKLISTED_IPS" | grep -q "$ip"; then
        echo "IP $ip already blocked. Skipping..."
        continue
    fi

    echo "Blocking malicious IP: $ip"
    ${iptables} -A INPUT -s "$ip" -j DROP

    # 查询IP归属地并保存到临时文件
    curl -s "http://www.cip.cc/$ip" > temp.txt
    query_result=$(grep "地址" temp.txt | awk -F ":" '{print $2}')
    echo "$ip: $query_result" >> "$OUTPUT_FILE"

    # 将IP添加到已拉黑列表
    echo "$ip" >> "$BLACKLISTED_IPS"

    # 删除临时文件
    rm temp.txt

    # 添加延迟，避免频繁查询
    sleep 2
done

# 保存防火墙规则
${iptables_save} >/dev/null
