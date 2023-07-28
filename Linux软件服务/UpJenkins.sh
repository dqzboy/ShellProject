#!/usr/bin/env bash
#===============================================================================
#
#          FILE: UpJenkins.sh
# 
#         USAGE: ./UpJenkins.sh
#
#   DESCRIPTION: 基于 Tomcat 部署的Jenkins版本更新脚本
# 
#  ORGANIZATION: DingQz dqzboy.com 浅时光博客
#===============================================================================

# 定义Jenkins下载链接和本地Tomcat目录
jenkins_base_url="https://mirrors.jenkins.io/war-stable"
tomcat_webapps_dir="/usr/local/tomcat/webapps"

# 备份旧的Jenkins目录
backup_dir="/tmp/jenkins_backup"
jenkins_dir="${tomcat_webapps_dir}/jenkins"

if [ -d "$jenkins_dir" ]; then
  echo "Backing up Jenkins directory..."
  backup_suffix=$(date +%Y%m%d-%H.%M)
  backup_name="jenkins_${backup_suffix}"
  mkdir -p "$backup_dir"
  cp -r "$jenkins_dir" "$backup_dir/$backup_name"
fi

# 提示用户输入Jenkins版本和SHA-256校验和
read -p $'\e[1;32m请输入想要下载的Jenkins版本号：\e[0m' version
read -p $'\e[1;32m请输入Jenkins war包的SHA-256校验和：\e[0m' sha256

# 构建Jenkins下载链接和校验和链接
jenkins_url="${jenkins_base_url}/${version}/jenkins.war"
sha256_url="${jenkins_base_url}/${version}/jenkins.war.sha256"

# 下载Jenkins war包和SHA-256校验和文件
echo "Downloading the Jenkins war file for version $version..."
wget "$jenkins_url"

# 计算下载的war包的SHA-256校验和
downloaded_sha256=$(sha256sum jenkins.war | awk '{print $1}')

# 校验下载的war包的SHA-256值
if [ "$downloaded_sha256" != "$sha256" ]; then
  echo $'\e[1;31m下载的Jenkins war包的SHA-256校验和不匹配，请重新下载！\e[0m'
  rm -f jenkins.war
  exit 1
fi

# 停止Tomcat服务
echo "Stopping Tomcat..."
systemctl stop tomcat

# 删除旧的Jenkins war包
if [ -f "${tomcat_webapps_dir}/jenkins.war" ]; then
  echo "Removing old Jenkins war file..."
  rm "${tomcat_webapps_dir}/jenkins.war"
fi

# 拷贝新的Jenkins war包到Tomcat目录
echo "Copying the Jenkins war file to Tomcat webapps..."
cp jenkins.war "${tomcat_webapps_dir}"
chown -R deploy. ${tomcat_webapps_dir}

rm -f $PWD/jenkins.war

sleep 3
# 启动Tomcat服务
echo "Starting Tomcat..."
systemctl restart tomcat

# 等待Tomcat启动完成
echo "Waiting for Tomcat to start..."
sleep 30

# 检查Tomcat是否成功启动
tomcat_status=$(sudo systemctl is-active tomcat)
if [ "$tomcat_status" == "active" ]; then
  echo $'\e[1;32mTomcat started successfully.\e[0m'
else
  echo $'\e[1;31mFailed to start Tomcat. Please check the logs.\e[0m'
fi
