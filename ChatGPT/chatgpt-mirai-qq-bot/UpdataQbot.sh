#!/bin/bash
SETCOLOR_SKYBLUE="echo -en \\E[1;36m"
SETCOLOR_SUCCESS="echo -en \\E[0;32m"
SETCOLOR_NORMAL="echo  -en \\E[0;39m"
SETCOLOR_RED="echo  -en \\E[0;31m"
echo
cat << EOF
 ██████╗ ██████╗ ████████╗     ██████╗  ██████╗     ██████╗  ██████╗ ████████╗
██╔════╝ ██╔══██╗╚══██╔══╝    ██╔═══██╗██╔═══██╗    ██╔══██╗██╔═══██╗╚══██╔══╝
██║  ███╗██████╔╝   ██║       ██║   ██║██║   ██║    ██████╔╝██║   ██║   ██║   
██║   ██║██╔═══╝    ██║       ██║▄▄ ██║██║▄▄ ██║    ██╔══██╗██║   ██║   ██║   
╚██████╔╝██║        ██║       ╚██████╔╝╚██████╔╝    ██████╔╝╚██████╔╝   ██║   
 ╚═════╝ ╚═╝        ╚═╝        ╚══▀▀═╝  ╚══▀▀═╝     ╚═════╝  ╚═════╝    ╚═╝   
                                                                              
EOF


SUCCESS() {
  ${SETCOLOR_SUCCESS} && echo ">>>>>>>> $1"  && ${SETCOLOR_NORMAL}
}

ERROR() {
  ${SETCOLOR_RED} && echo ">>>>>>>> $1"  && ${SETCOLOR_NORMAL}
}

INFO() {
  ${SETCOLOR_SKYBLUE} && echo ">>>>>>>> $1"  && ${SETCOLOR_NORMAL}
}
# 检查/opt目录下是否存在config.cfg文件
if [ -f "/opt/config.cfg" ]; then
  # 如果存在，则删除旧的并拷贝新的
  rm /opt/config.cfg
  SUCCESS "旧版备份文件存在，执行删除"
  cp /data/chatgpt-mirai-qq-bot/config.cfg /opt/config.cfg
  \cp /data/chatgpt-mirai-qq-bot/config.cfg /data/config_bak/
  SUCCESS "拷贝新文件进行备份完成！"
else
  ERROR "配置文件不存在，退出升级！"
  exit 1
fi

# 下载最新版本
if [ -f "/opt/config.cfg" ]; then
  SUCCESS "配置文件已备份，执行项目升级..."
  # 再次检测，如果上面备份了配置文件，则进行删除旧项目克隆新版本
  # 检查/data目录下是否存在chatgpt-mirai-qq-bot目录
  if [ -d "/data/chatgpt-mirai-qq-bot" ]; then
    # 如果存在，则删除
    rm -rf /data/chatgpt-mirai-qq-bot
    SUCCESS "旧版项目存在,已删除!"
    cd /data
    git clone https://github.com/lss233/chatgpt-mirai-qq-bot
    cd chatgpt-mirai-qq-bot
    pip3 install -r requirements.txt &>/dev/null

    # 拷贝配置文件并重启服务
    cp /opt/config.cfg ./
    systemctl restart qqbot.service
    INFO "新版本升级完成！！"
  else
    ERROR "配置文件未备份，请备份之后再进行升级项目！！"
  fi
fi
