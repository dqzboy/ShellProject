#!/usr/bin/env bash
#===============================================================================
#
#          FILE: malicious_ip_blocker.sh
# 
#         USAGE: ./malicious_ip_blocker.sh
#   DESCRIPTION: lastb获取登入失败的IP，调用 iptables 限制恶意尝试登入的IP
#   在 /opt 目录下手动创建whitelist.txt白名单文件，并写入白名单IP，每行一个IP
#   crontab eg：0 0 * * * /bin/bash malicious_ip_blocker.sh > /tmp/malicious_ip_blocker.log 2>&1 && echo "[执行时间: $(date '+\%Y-\%m-\%d \%H:\%M:\%S')]" >> /tmp/malicious_ip_blocker.log
#  ORGANIZATION: dqzboy.com
#===============================================================================

#!/usr/bin/env bash
iptables=$(command -v iptables)
iptables_save=$(command -v iptables-save)

# 获取登录失败的IP地址（仅提取有效的IP地址）
MALICIOUS_IPS=$(lastb -i | awk '$3 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {print $3}' | sort | uniq)

# 黑白名单存储的目录
CURR_DIR="/opt"
# 文件保存查询结果
OUTPUT_FILE="${CURR_DIR}/malicious_ips.txt"
# 之前已被拉黑的IP地址列表
BLACKLISTED_IPS="${CURR_DIR}/blacklisted_ips.txt"

# 白名单IP文件
WHITELIST_FILE="${CURR_DIR}/whitelist.txt"

# 交互式输入白名单IP;如果是要配合定时任务执行脚本,那么这里就不要开启交互式,而是提前创建白名单文件并把IP写入到白名单文件中
#read -e -p "请输入白名单IP（多个IP以英文逗号分隔）：" WHITELIST_INPUT

# 将用户输入的白名单IP写入白名单文件
#echo "$WHITELIST_INPUT" | tr ',' '\n' > "$WHITELIST_FILE"

# 从之前已拉黑的IP文件中读取
if [ -f "$BLACKLISTED_IPS" ]; then
    PREVIOUSLY_BLACKLISTED_IPS=$(cat "$BLACKLISTED_IPS")
else
    PREVIOUSLY_BLACKLISTED_IPS=""
fi

# 如果白名单文件存在，读取白名单IP
if [ -f "$WHITELIST_FILE" ]; then
    WHITELIST=$(cat "$WHITELIST_FILE")
else
    WHITELIST=""
fi

# 清空文件内容
> "$OUTPUT_FILE"

# 遍历恶意IP地址列表，添加防火墙规则并查询IP归属地
for ip in $MALICIOUS_IPS; do
    # 如果IP已在白名单中，跳过
    if echo "$WHITELIST" | grep -q "$ip"; then
        echo "IP $ip is whitelisted. Skipping..."
        continue
    fi

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
