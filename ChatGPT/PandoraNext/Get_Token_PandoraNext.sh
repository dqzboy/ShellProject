#!/usr/bin/env bash
#===============================================================================
#
#          FILE: Get_Token_PandoraNext.sh
#
#         USAGE: ./Get_Token_PandoraNext.sh
#
#   DESCRIPTION: 调用接口获取PandoraNext各Token
#
#  ORGANIZATION: DingQz dqzboy.com
#===============================================================================

# 全局变量定义
proxy_api_prefix="<your_proxy_api_prefix>"
user_email="<your_user_email>"
passwd="<your_passwd>"

# 执行curl请求并将JSON响应存储在变量中
response=$(curl -s "http://127.0.0.1:8181/${proxy_api_prefix}/api/auth/login" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    -d "username=${user_email}" \
    -d "password=${passwd}")

# 删除换行符
response=$(echo "$response" | tr -d '\n')

# 检查是否成功获取access_token
if [ "$(echo "$response" | jq -r '.access_token')" == "null" ]; then
    # 打印错误信息，并退出脚本
    echo -e "\e[31mError: Failed to retrieve access token.\e[0m"
    exit 1
fi

# 使用jq提取access_token
access_token=$(echo "$response" | jq -r '.access_token')

# 设置文本颜色为绿色，并打印提取的access_token
echo -e "\e[32mAccess Token: $access_token\e[0m"

# 定义保存token的文件路径
token_file="token_file.txt"
share_token_file="share_token_file.txt"

# 将token写入文件
echo "access_token = \"$access_token\"" > "$token_file"

# 提示token已保存
echo -e "\e[33mAccess Token已保存到文件: $token_file\e[0m"
echo "------------------------------------------------------------"
# 询问用户是否获取Share Token
read -p "是否获取Share Token? (y/n): " get_share_token

# 根据用户输入决定是否执行下面的命令
if [ "$get_share_token" == "y" ]; then
    # 执行获取Share Token的命令，替换 ${access_token} 为实际的access_token
    share_token_response=$(curl -s "http://127.0.0.1:8181/${proxy_api_prefix}/api/token/register" \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        -d 'unique_name=Pandora' \
        -d "access_token=${access_token}" \
        -d 'site_limit=https%3A%2F%2Fchat.oaifree.com' \
        -d 'expires_in=0' \
        -d 'show_conversations=false' \
        -d 'show_userinfo=false')

    # 使用jq提取token_key
    share_token=$(echo "$share_token_response" | jq -r '.token_key')

    # 打印提取的token_key
    echo -e "\e[32mShare Token: $share_token\e[0m"
    # 将token_key写入文件
    echo "Share Token = \"$share_token\"" > "$share_token_file"
    echo -e "\e[33mShare Token已保存到文件: $share_token_file\e[0m"
else
    echo "未获取Share Token."
fi
