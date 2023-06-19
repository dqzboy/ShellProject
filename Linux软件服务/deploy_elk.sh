#!/usr/bin/env bash
#===============================================================================
#
#          FILE: deploy_elk.sh
# 
#         USAGE: ./deploy_elk.sh
#
#   DESCRIPTION: ELK单机一键部署脚本
# 
#  ORGANIZATION: DingQz dqzboy.com 浅时光博客
#===============================================================================
 
SETCOLOR_SKYBLUE="echo -en \\E[1;36m"
SETCOLOR_SUCCESS="echo -en \\E[0;32m"
SETCOLOR_NORMAL="echo  -en \\E[0;39m"
SETCOLOR_RED="echo  -en \\E[0;31m"
SETCOLOR_YELLOW="echo -en \\E[1;33m"
 
# 包存放目录
mkdir -p /opt/soft
yum install lsof -y &>/dev/null
echo
cat << \EOF
$$$$$$$$\ $$\       $$\   $$\       $$$$$$$$\  $$$$$$\   $$$$$$\  $$\       $$$$$$\  
$$  _____|$$ |      $$ | $$  |      \__$$  __|$$  __$$\ $$  __$$\ $$ |     $$  __$$\ 
$$ |      $$ |      $$ |$$  /          $$ |   $$ /  $$ |$$ /  $$ |$$ |     $$ /  \__|
$$$$$\    $$ |      $$$$$  /           $$ |   $$ |  $$ |$$ |  $$ |$$ |     \$$$$$$\  
$$  __|   $$ |      $$  $$<            $$ |   $$ |  $$ |$$ |  $$ |$$ |      \____$$\ 
$$ |      $$ |      $$ |\$$\           $$ |   $$ |  $$ |$$ |  $$ |$$ |     $$\   $$ |
$$$$$$$$\ $$$$$$$$\ $$ | \$$\          $$ |    $$$$$$  | $$$$$$  |$$$$$$$$\\$$$$$$  |
\________|\________|\__|  \__|         \__|    \______/  \______/ \________|\______/ 
                                                                                     
                                                                                     
                                                                                     
EOF
 
SUCCESS() {
  ${SETCOLOR_SUCCESS} && echo "------------------------------------< $1 >-------------------------------------"  && ${SETCOLOR_NORMAL}
}
 
SUCCESS1() {
  ${SETCOLOR_SUCCESS} && echo " $1 "  && ${SETCOLOR_NORMAL}
}
 
ERROR() {
  ${SETCOLOR_RED} && echo " $1 "  && ${SETCOLOR_NORMAL}
}
 
INFO() {
  ${SETCOLOR_SKYBLUE} && echo " $1 "  && ${SETCOLOR_NORMAL}
}
 
WARN() {
  ${SETCOLOR_YELLOW} && echo " $1 "  && ${SETCOLOR_NORMAL}
}
 
function CHECK_IP() {
SUCCESS "根据提示输入信息"
# 提示用户输入IP地址
read -e -p "请输入ES地址 (回车获取本机IP): " ip
 
while [[ -z "$ip" ]]; do
  # 如果用户未输入IP，则获取本机IP
  ip=$(hostname -I | awk '{print $1}')
 
  # 输出获取到的IP并向用户确认是否使用
  INFO "获取到的IP地址为: $ip"
  read -e -p "是否使用该IP地址? [y/n]: " confirm
 
  if [[ "$confirm" == "y" ]] || [[ "$confirm" == "Y" ]]; then
    break
  else
    unset ip
    SUCCESS1 "请重新输入IP地址"
    read -e -p "请输入IP地址: " ip
  fi
done
 
SUCCESS1 "使用IP地址: $ip"
}
 
function CHECK_VER() {
# 提示用户输入3个版本号，以空格分隔
read -e -p "请输入要安装的 ES,Logstash,Kibana 版本号,以空格分隔(eg: 8.7.1 8.7.1 8.7.1): " ever lver kver
 
while [[ -z "$ever" ]] || [[ -z "$lver" ]] || [[ -z "$kver" ]]; do
  ERROR "版本号不能为空且只能输入3个参数，请重新输入"
  read -e -p "请输入要安装的 ES,Logstash,Kibana 版本号,以空格分隔(eg: 8.7.1 8.7.1 8.7.1): " ever lver kver
done
 
SUCCESS1 "使用 ES 版本号: $ever"
SUCCESS1 "使用 Logstash 版本号: $lver"
SUCCESS1 "使用 Kibana   版本号: $kver"
}
 
function CHECK_WGET() {
# 检查是否已安装wget
SUCCESS "开始执行安装"
if ! command -v wget &> /dev/null; then
    WARN "wget is not installed. Installing..."
    
    # 根据不同的Linux发行版执行安装命令
    if [[ -f /etc/redhat-release ]]; then
        # CentOS 或 Red Hat 系统
        sudo yum install -y wget &>/dev/null
    
    elif [[ -f /etc/lsb-release ]]; then
        # Ubuntu 或 Debian 系统
        sudo apt-get update &>/dev/null
        sudo apt-get install -y wget &>/dev/null
    
    else
        ERROR "Unsupported distribution."
        exit 1
    fi
    
else
    SUCCESS1 "wget is already installed."
fi
}
 
 
# 安装 elasticsearch
function INSTALL_ES() {
SUCCESS "安装elasticsearch"
# 拼接下载链接和目标文件夹路径
url="https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-${ever}-linux-x86_64.tar.gz"
 
target_dir="/usr/local/elasticsearch"
 
# 下载并解压安装包
cd /opt/soft/
wget "$url"
tar -xf "elasticsearch-${ever}-linux-x86_64.tar.gz" -C /usr/local
mv "/usr/local/elasticsearch-${ever}" "$target_dir"
useradd -M -s /sbin/nologin elasticsearch &>/dev/null
chown -R elasticsearch. /usr/local/elasticsearch
 
cat > /usr/lib/systemd/system/elasticsearch.service <<EOF
[Unit]
Description=elasticsearch
Documentation=https://www.elastic.co/
Wants=network-online.target
After=network.target network-online.target
 
[Service]
Type=simple
User=elasticsearch
Group=elasticsearch
ExecStart=/usr/local/elasticsearch/bin/elasticsearch
ExecReload=/bin/kill --signal HUP
KillMode=control-group
KillSignal=SIGTERM
Restart=on-failure
LimitNOFILE=65536
LimitMEMLOCK=infinity
 
[Install]
WantedBy=multi-user.target
EOF
 
systemctl daemon-reload
systemctl restart elasticsearch
systemctl enable elasticsearch
 
while true; do
  # 检查 Elasticsearch 服务状态
  status=$(systemctl is-active elasticsearch)
 
  if [[ "$status" == "active" ]]; then
    # 检查端口是否监听
    if lsof -i :9200 | grep LISTEN >/dev/null; then
       SUCCESS1 "Elasticsearch 服务已成功启动，并监听端口 9200"
       break  # 退出循环
    fi
  fi
 
  sleep 10  # 等待10秒后再次检查
done
# 打印安装成功消息
SUCCESS1 "Elasticsearch ${ever} 安装完成！安装路径: $target_dir"
}
 
 
# 安装 logstash
function INSTALL_LOG() {
SUCCESS "安装 logstash"
# 拼接下载链接和目标文件夹路径
url="https://artifacts.elastic.co/downloads/logstash/logstash-${lver}-linux-x86_64.tar.gz"
 
target_dir="/usr/local/logstash"
 
# 下载并解压安装包
cd /opt/soft/
wget "$url"
tar -xf "logstash-${ever}-linux-x86_64.tar.gz" -C /usr/local
mv "/usr/local/logstash-${ever}" "$target_dir"
useradd -M -s /sbin/nologin logstash &>/dev/null
chown -R logstash. /usr/local/logstash/
 
cat > /usr/lib/systemd/system/logstash.service <<EOF
[Unit]
Description=logstash
 
[Service]
Type=simple
User=logstash
Group=logstash
EnvironmentFile=-/etc/sysconfig/logstash
ExecStart=/usr/local/logstash/bin/logstash "--path.settings" "/usr/local/logstash/config"
 
Restart=always
WorkingDirectory=/
Nice=19
LimitNOFILE=65536
 
[Install]
WantedBy=multi-user.target
EOF
 
systemctl daemon-reload
systemctl restart logstash
systemctl enable logstash
 
while true; do
  # 检查 logstash 服务状态
  status=$(systemctl is-active logstash)
 
  if [[ "$status" == "active" ]]; then
     SUCCESS1 "Logstash 服务已成功启动"
     WARN "Pipelines YAML file is empty. Location: /usr/local/logstash/config/pipelines.yml"
     break  # 退出循环
  fi
 
  sleep 10  # 等待10秒后再次检查
done
# 打印安装成功消息
SUCCESS1 "logstash ${lver} 安装完成！安装路径: $target_dir"
}
 
# 安装 Kibana
function INSTALL_KIBANA() {
SUCCESS "安装 Kibana"
# 拼接下载链接和目标文件夹路径
url="https://artifacts.elastic.co/downloads/kibana/kibana-${kver}-linux-x86_64.tar.gz"
 
target_dir="/usr/local/kibana"
 
# 下载并解压安装包
cd /opt/soft/
wget "$url"
tar -xf "kibana-${ever}-linux-x86_64.tar.gz" -C /usr/local
mv "/usr/local/kibana-${ever}" "$target_dir"
useradd -M -s /sbin/nologin kibana &>/dev/null
chown -R kibana. /usr/local/kibana/
 
cat > /usr/lib/systemd/system/kibana.service <<EOF
[Unit]
Description=Kibana
Documentation=https://www.elastic.co
Wants=network-online.target
After=network-online.target
 
[Service]
Type=simple
User=kibana
Group=kibana
PrivateTmp=true
 
Environment=KBN_PATH_CONF=/usr/local/kibana/config
EnvironmentFile=-/etc/sysconfig/kibana
ExecStart=/usr/local/kibana/bin/kibana
 
Restart=on-failure
RestartSec=3
 
StartLimitBurst=3
StartLimitInterval=60
 
WorkingDirectory=/usr/local/kibana
 
StandardOutput=journal
StandardError=inherit
 
[Install]
WantedBy=multi-user.target
EOF
 
systemctl daemon-reload
systemctl restart kibana
systemctl enable kibana
 
while true; do
  # 检查 kibana 服务状态
  status=$(systemctl is-active kibana)
 
  if [[ "$status" == "active" ]]; then
    # 检查端口是否监听
    # 检查端口是否监听
    if lsof -i :5601 | grep LISTEN >/dev/null; then
       SUCCESS1 "Kibana 服务已成功启动，并监听端口 5601"
       break  # 退出循环
    fi
  fi
 
  sleep 10  # 等待10秒后再次检查
done
# 打印安装成功消息
SUCCESS1 "Kibana ${kver} 安装完成！安装路径: $target_dir"
}
 
function DONE() {
SUCCESS "部署完成,请根据实际情况修改配置."
INFO "ES配置：/usr/local/elasticsearch/config/elasticsearch.yml"
INFO "Logstash配置：/usr/local/logstash/config/logstash.yml"
INFO "Kibana配置：/usr/local/kibana/config/kibana.yml"
SUCCESS " END "
}
 
main() {
  CHECK_WGET
  CHECK_IP
  CHECK_VER
  INSTALL_ES
  INSTALL_LOG
  INSTALL_KIBANA
  DONE
}
main
