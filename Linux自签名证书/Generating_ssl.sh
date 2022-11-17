#!/usr/bin/env bash

#===============================================================================
#
#          FILE: Generating_ssl.sh
# 
#         USAGE: bash Generating_ssl.sh
#   DESCRIPTION: 基于cfssl工具实现自签名SSL服务器证书
# 
#  ORGANIZATION: dqzboy.com
#       CREATED: 2022
#===============================================================================

## 安装部署cfssl工具
ADD_CFSSL() {
echo
echo "-------------------------------------<提 示>-------------------------------------"
echo "                           检查服务器是否安装CFSSL工具!"
echo "-------------------------------------< END >-------------------------------------"
echo

cfsslVer="1.6.3"
if [ -f /usr/local/bin/cfssl ];then
    echo "Skip..."
else
    wget https://ghproxy.com/https://github.com/cloudflare/cfssl/releases/download/v${cfsslVer}/cfssl_${cfsslVer}_linux_amd64
    mv cfssl_${cfsslVer}_linux_amd64 /usr/local/bin/cfssl
fi

if [ -f /usr/local/bin/cfssl-certinfo ];then
    echo "Skip..."
else
    wget https://ghproxy.com/https://github.com/cloudflare/cfssl/releases/download/v${cfsslVer}/cfssl-certinfo_${cfsslVer}_linux_amd64
    mv cfssl-certinfo_${cfsslVer}_linux_amd64 /usr/local/bin/cfssl-certinfo
fi

if [ -f /usr/local/bin/cfssljson ];then
    echo "Skip..."
else
    wget https://ghproxy.com/https://github.com/cloudflare/cfssl/releases/download/v${cfsslVer}/cfssljson_${cfsslVer}_linux_amd64
    mv cfssljson_${cfsslVer}_linux_amd64 /usr/local/bin/cfssljson
fi
# 赋予执行权限
chmod +x /usr/local/bin/cfssl*


cfssl version
}
## 生成CA证书
CA_NAMES() {
mkdir -p /data/cert && cd /data/cert
echo
echo "-------------------------------------<提 示>-------------------------------------"
echo "                               直接回车,使用默认值!"
echo "-------------------------------------< END >-------------------------------------"
echo
read -p "请输入证书过期时间[16800h(1年|Default)|19800h(825天)|168000(10年)]：" input
if [ -z "${input}" ];then
    input="16800h"
    echo ${input}
fi
echo "-------------------------------------------------------------------------------------"
read -p "请输入域名[不可缺失!]：" inputURL
if [ -z "${inputURL}" ];then
    echo "参数为空,退出执行"
    exit 1
fi
echo "-------------------------------------------------------------------------------------"
read -p "请输入国家[Default: CN]：" inputC
if [ -z "${inputC}" ];then
    inputC="CN"
    echo ${inputC}
fi
echo "-------------------------------------------------------------------------------------"
read -p "请输入地区、城市[Default: Shanghai]：" inputL
if [ -z "${inputL}" ];then
    inputL="Shanghai"
fi
echo "-------------------------------------------------------------------------------------"
read -p "请输入州、省[Default: Shanghai]：" inputST
if [ -z "${inputST}" ];then
    inpuST="Shanghai"
fi
echo "-------------------------------------------------------------------------------------"
read -p "请输入组织名称，公司名称[Default: DEVOPS]：" inputO
if [ -z "${inputO}" ];then
    inpuO="Shanghai"
fi
echo "-------------------------------------------------------------------------------------"
read -p "请输入组织单位名称，公司部门[Default: DEVOPS]：" inputOU
if [ -z "${inputOU}" ];then
    inpuOU="Shanghai"
fi
echo "-------------------------------------------------------------------------------------"
}

CREATE_CA() {
echo "================================================< CA CONFIG >================================================"
cat > ca-config.json <<EOF
{
    "signing": {
        "default": {
            "expiry": "${input}"
        },
        "profiles": {
            "Server": {
                "expiry": "${input}",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth"
                ]
            },
            "Client": {
                "expiry": "${input}",
                "usages": [
                    "signing",
                    "key encipherment",
                    "client auth"
                ]
            }
        }
    }
}
EOF

echo "================================================< CA CSR >================================================"
cat > ca-csr.json <<EOF
{
    "CN": "${inputURL}",
    "hosts": [
        "${inputURL}"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "${inputC}",
            "ST": "${inputST}",
            "L": "${inputL}",
            "O": "${inputO}",
            "OU": "${inputOU}"
        }
    ]
}
EOF

echo "==================================================< CA CREATE  >=================================================="
cfssl gencert -initca ca-csr.json | cfssljson -bare ca
echo "================================================< CA CREATE DONE >================================================"

}

CREATE_SERVER() {
mkdir -p /data/cert/${inputURL} && cd /data/cert/${inputURL}
echo "================================================< SERVER CSR >================================================"
cat > ${inputURL}-csr.json <<EOF
{
    "CN": "${inputURL}",
    "hosts": [
        "${inputURL}"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "${inputC}",
            "ST": "${inputST}",
            "L": "${inputL}",
            "O": "${inputO}",
            "OU": "${inputOU}"
        }
    ]
}
EOF

echo "================================================<SERVER SSL CREATE>================================================"
cfssl gencert -ca=/data/cert/ca.pem -ca-key=/data/cert/ca-key.pem -config=/data/cert/ca-config.json -profile=Server ${inputURL}-csr.json | cfssljson -bare ${inputURL}
echo "================================================< SERVER SSL DONE >================================================"
}

main() {
    ADD_CFSSL	
    CA_NAMES
    CREATE_CA
    CREATE_SERVER
}
main
