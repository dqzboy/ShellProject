#!/bin/bash
#===============================================================================
#
#          FILE: install_elk762.sh
# 
#         USAGE: ./install_elk762.sh
#   DESCRIPTION: 一键部署ELK服务
# 
#  ORGANIZATION: dqzboy.com
#===============================================================================

export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

alias mv='mv'
alias rm='rm'

if [ ! -z "$(netstat -nptl|grep ^tcp6)" ];then
   echo "没有关闭IPV6，退出！"
   exit
fi

if [ "$(free -g|awk '/^Mem/{print $2-$3}')" -le 4 ];then
   echo "可用内存小于4g，退出！"
fi

#安装依赖软件
yum -y install java-11-openjdk nodejs npm git bzip2 log4j* net-tools

systemctl stop es 2>/dev/null
systemctl stop kibana 2>/dev/null
systemctl stop logstash 2>/dev/null

#下载软件
if [ ! -e elasticsearch-7.6.2-linux-x86_64.tar.gz ];then
    wget -c https://mirrors.huaweicloud.com/elasticsearch/7.6.2/elasticsearch-7.6.2-linux-x86_64.tar.gz
fi

if [ ! -e kibana-7.6.2-linux-x86_64.tar.gz ];then
    wget -c https://mirrors.huaweicloud.com/kibana/7.6.2/kibana-7.6.2-linux-x86_64.tar.gz
fi

if [ ! -e logstash-7.6.2.tar.gz ];then
    wget -c https://mirrors.huaweicloud.com/logstash/7.6.2/logstash-7.6.2.tar.gz
fi

if [ ! -e elasticsearch-7.6.2-linux-x86_64.tar.gz ];then
   echo "没下载 elasticsearch-7.6.2-linux-x86_64.tar.gz 文件，退出安装！"
   exit
fi

if [ ! -e kibana-7.6.2-linux-x86_64.tar.gz ];then
   echo "没下载 kibana-7.6.2-linux-x86_64.tar.gz 文件，退出安装！"
   exit
fi

if [ ! -e logstash-7.6.2.tar.gz ];then
   echo "没下载 logstash-7.6.2.tar.gz 文件，退出安装！"
   exit
fi

rm -rf elasticsearch-7.6.2 2>/dev/null
rm -rf kibana-7.6.2-linux-x86_64 2>/dev/null
rm -rf logstash-7.6.2 2>/dev/null
rm -rf /opt/es 2>/dev/null
rm -rf /opt/logstash 2>/dev/null
rm -rf /opt/kibana 2>/dev/null

if [ -e /opt/es_data ];then
    echo "/opt/es_data目录已存在，请确认没有数据，删除后在重新进行安装！" 
    exit
fi


#优化系统
if [ -z "$(grep vm.max_map_count /etc/sysctl.conf)" ];then
   echo 'vm.max_map_count=655360' >>/etc/sysctl.conf
else
   sed -i 's/vm.max_map_count.*/vm.max_map_count=655360/g' /etc/sysctl.conf
fi

if [ -z "$(grep vm.swappiness /etc/sysctl.conf)" ];then
   echo 'vm.swappiness=10' >>/etc/sysctl.conf
else
   sed -i 's/vm.swappiness.*/vm.swappiness=10/g' /etc/sysctl.conf
fi

sysctl -p
ulimit -SHn 655360

#安装es
tar zxvf elasticsearch-7.6.2-linux-x86_64.tar.gz
if [ $? != 0 ];then
    echo "解压错误，文件不完整！"
    exit
fi

cp -rf elasticsearch-7.6.2 /opt/es
useradd es -d /opt/es
mkdir -p /opt/es_data /opt/es_logs
chown -R es:es /opt/es_data /opt/es_logs /opt/es
chmod -R 777 /opt/es_data /opt/es_logs
wget -O /opt/es/config/elasticsearch.yml http://www.bigops.com/bigops-install/elk/elasticsearch.yml

#安装kibana
tar zxvf kibana-7.6.2-linux-x86_64.tar.gz
if [ $? != 0 ];then
    echo "解压错误，文件不完整！"
    exit
fi

cp -rf kibana-7.6.2-linux-x86_64 /opt/kibana
wget -O /opt/kibana/config/kibana.yml http://www.bigops.com/bigops-install/elk/kibana.yml

#安装logstash
tar zxvf logstash-7.6.2.tar.gz
if [ $? != 0 ];then
    echo "解压错误，文件不完整！"
    exit
fi

cp -rf logstash-7.6.2 /opt/logstash

if [ ! -d /opt/logstash-conf ];then
    mkdir /opt/logstash-conf
fi

wget -O /opt/logstash-conf/syslog.conf http://www.bigops.com/bigops-install/elk/syslog.conf
wget -O /opt/logstash-conf/winlog.conf http://www.bigops.com/bigops-install/elk/winlog.conf

# echo
# echo -e "输入分配给ES内存的大小（最小4G，默认4G）：\c"
# read esmemsize

#if [ -z "${esmemsize}" ];then
#    esmemsize=4g
#fi

# esmemsize=`echo "${esmemsize}"|sed 's/G$//g'`
# esmemsize=`echo "${esmemsize}"|sed 's/g$//g'`

# if [ "${esmemsize}" -lt 4 ];then
#     echo "给ES分配的内存不能少于4G，退出安装！"
#     exit
# fi

# esmemsize=`echo "${esmemsize}"|sed 's/$/g/g'`

esmemsize=4g

sed -i 's/^-Xms1g/-Xms'"${esmemsize}"'/g' /opt/es/config/jvm.options
sed -i 's/^-Xmx1g/-Xmx'"${esmemsize}"'/g' /opt/es/config/jvm.options
sed -i 's/^-XX:+UseConcMarkSweepGC/#-XX:+UseConcMarkSweepGC/g' /opt/es/config/jvm.options
sed -i 's/^-XX:CMSInitiatingOccupancyFraction=75/#-XX:CMSInitiatingOccupancyFraction=75/g' /opt/es/config/jvm.options
sed -i 's/^-XX:+UseCMSInitiatingOccupancyOnly/#-XX:+UseCMSInitiatingOccupancyOnly/g' /opt/es/config/jvm.options

sed -i 's/^8-13:-XX:+UseConcMarkSweepGC/#8-13:-XX:+UseConcMarkSweepGC/g' /opt/es/config/jvm.options
sed -i 's/^8-13:-XX:CMSInitiatingOccupancyFraction=75/#8-13:-XX:CMSInitiatingOccupancyFraction=75/g' /opt/es/config/jvm.options
sed -i 's/^8-13:-XX:+UseCMSInitiatingOccupancyOnly/#8-13:-XX:+UseCMSInitiatingOccupancyOnly/g' /opt/es/config/jvm.options

sed -i '/^-XX:+UseG1GC/d' /opt/es/config/jvm.options
sed -i '/^-XX:MaxGCPauseMillis=.*/d' /opt/es/config/jvm.options
echo '-XX:+UseG1GC' >>/opt/es/config/jvm.options
echo '-XX:MaxGCPauseMillis=200' >>/opt/es/config/jvm.options

echo
echo
echo -e "本机所有IP供参考，如果是云主机弹性IP这里不会显示。"
ifconfig -a|grep inet|awk '{print $2}'|sed 's/addr://g'|grep -Ev '(127.0.0.1|::)'

echo
echo -e "输入当前主机IP，用于ES监听：\c"
read ip

if [ -z "${ip}" ];then
   echo "ES监听IP不能为空，请重新运行安装程序，退出安装！"
   exit
fi

sed -i 's/^node.name:.*/node.name: '"${ip}"'/g' /opt/es/config/elasticsearch.yml
sed -i 's/^cluster.initial_master_nodes:.*/cluster.initial_master_nodes: [\"'"${ip}"':9300\"]/g' /opt/es/config/elasticsearch.yml
sed -i 's/^discovery.seed_hosts:.*/discovery.seed_hosts: [\"'"${ip}"':9300\"]/g' /opt/es/config/elasticsearch.yml

#修改kibana配置文件
echo
echo -e "设置ES连接密码：\c"
read es_pass
if [ ! -z "${es_pass}" ];then
    sed -i "s/^elasticsearch.password:.*/elasticsearch.password: \""${es_pass}"\"/g" /opt/kibana/config/kibana.yml
fi

#修改logstash配置文件
if [ ! -z "${es_pass}" ];then
    sed -i "s#^[ ]*hosts => \[\".*#        hosts => [\""${ip}":9200\"]#g" /opt/logstash-conf/syslog.conf
    sed -i "s#^[ ]*password => \".*#        password => \""${es_pass}"\"#g" /opt/logstash-conf/syslog.conf
    sed -i "s#^[ ]*hosts => \[\".*#        hosts => [\""${ip}":9200\"]#g" /opt/logstash-conf/winlog.conf
    sed -i "s#^[ ]*password => \".*#        password => \""${es_pass}"\"#g" /opt/logstash-conf/winlog.conf
fi

sed -i '/^*.notice @@'"${ip}".*'/d' /etc/rsyslog.conf
echo "*.notice @@${ip}:6514" >/etc/rsyslog.d/bigops.conf
systemctl restart rsyslog

sed -i 's#^LS_HOME=.*#LS_HOME=/opt/logstash#g' /opt/logstash/config/startup.options
sed -i 's#^LS_SETTINGS_DIR=.*#LS_SETTINGS_DIR=/opt/logstash/config#g' /opt/logstash/config/startup.options
sed -i 's#^LS_OPTS=.*#LS_OPTS="--path.settings ${LS_SETTINGS_DIR} -f /opt/logstash-conf"#g' /opt/logstash/config/startup.options
sed -i 's#^LS_USER=.*#LS_USER=root#g' /opt/logstash/config/startup.options
sed -i 's#^LS_GROUP=.*#LS_GROUP=root#g' /opt/logstash/config/startup.options

/opt/logstash/bin/system-install

if [ -e /usr/bin/systemctl ];then  
    wget -O /usr/lib/systemd/system/es.service http://www.bigops.com/bigops-install/elk/es.service
    systemctl enable es
    systemctl daemon-reload
    systemctl restart es.service
    systemctl status es.service
    sleep 10

    wget -O /usr/lib/systemd/system/kibana.service http://www.bigops.com/bigops-install/elk/kibana.service
    systemctl enable kibana
    systemctl daemon-reload
    systemctl enable logstash
    systemctl daemon-reload
fi

if [ ! -z "$(ls -d /usr/lib/jvm/java-11-openjdk-*|grep -v debug|head -n 1)" ];then
    javahome=$(ls -d /usr/lib/jvm/java-11-openjdk-*|grep -v debug|head -n 1)
    sed -i '/^export PATH=.*/d' /opt/es/bin/elasticsearch
    sed -i '/^export JAVA_HOME=.*/d' /opt/es/bin/elasticsearch
    sed -i 'N;2 a export PATH=$JAVA_HOME/bin:$PATH' /opt/es/bin/elasticsearch
    sed -i "N;2 a export JAVA_HOME="${javahome}"" /opt/es/bin/elasticsearch
    sed -i '/^export PATH=.*/d' /opt/es/bin/elasticsearch-env
    sed -i '/^export JAVA_HOME=.*/d' /opt/es/bin/elasticsearch-env
    sed -i 'N;2 a export PATH=$JAVA_HOME/bin:$PATH' /opt/es/bin/elasticsearch-env
    sed -i "N;2 a export JAVA_HOME="${javahome}"" /opt/es/bin/elasticsearch-env
    sed -i '/^export PATH=.*/d' /opt/es/bin/elasticsearch-setup-passwords
    sed -i '/^export JAVA_HOME=.*/d' /opt/es/bin/elasticsearch-setup-passwords
    sed -i 'N;2 a export PATH=$JAVA_HOME/bin:$PATH' /opt/es/bin/elasticsearch-setup-passwords
    sed -i "N;2 a export JAVA_HOME="${javahome}"" /opt/es/bin/elasticsearch-setup-passwords
else
    echo "目录/usr/lib/jvm/下没发现java11，退出安装！"
fi

echo
echo "后续步骤一：设置ES密码"
echo "-------------------"
echo "等待10秒后，查看ES是否启动，运行命令："
echo "netstat -nptl|grep 9[2,3]00"
echo "如果没有启动，请尝试手动启动："
echo "su - es"
echo "/opt/es/bin/elasticsearch"
echo 
echo "9200和9300端口启动后，运行下面命令设置密码"
echo "/opt/es/bin/elasticsearch-setup-passwords interactive"
echo "Please confirm that you would like to continue [y/N]，回答y"
echo "要设置的密码比较多，都设置成ES连接密码"
echo "-------------------"
echo 
echo "后续步骤二：启动kibana"
echo "-------------------"
echo "运行命令"
echo "systemctl restart kibana.service"
echo
echo "等待10秒后，查看端口是否启动，运行命令"
echo "netstat -nplt|grep 5601"
echo
echo "5601端口启动后，使用浏览器访问：http://${ip}:5601"
echo "默认登录用户名：elastic"
echo "密码：刚才设置的ES连接密码"
echo
echo "后续步骤三：启动logstash"
echo "-------------------"
echo "运行命令"
echo "systemctl restart logstash.service"
echo
echo "等待10秒后，查看端口是否启动，运行命令"
echo "netstat -npl|grep 6514"
echo "-------------------"
echo
