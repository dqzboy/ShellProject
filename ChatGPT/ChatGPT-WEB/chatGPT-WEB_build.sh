#!/usr/bin/env bash
#===============================================================================
#
#          FILE: build.sh
# 
#         USAGE: bash build.sh
#
#   DESCRIPTION: chatGPT-WEB项目构建脚本
# 
#  ORGANIZATION: DingQz dqzboy.com
#===============================================================================

SETCOLOR_SKYBLUE="echo -en \\E[1;36m"
SETCOLOR_SUCCESS="echo -en \\E[0;32m"
SETCOLOR_NORMAL="echo  -en \\E[0;39m"
SETCOLOR_RED="echo  -en \\E[0;31m"

# 定义项目仓库地址
GITGPT="https://github.com/Chanzhaoyu/chatgpt-web"
# 定义需要拷贝的文件目录
CHATDIR="chatgpt-web"
SERDIR="service"
FONTDIR="dist"
ORIGINAL=${PWD}

function GITCLONE() {
${SETCOLOR_SUCCESS} && echo "-------------------------------------<项目克隆>-------------------------------------" && ${SETCOLOR_NORMAL}
${SETCOLOR_SUCCESS}
${SETCOLOR_RED} && echo "                           注: 国内服务器请选择参数 2 "
${SETCOLOR_SUCCESS} && echo "-------------------------------------< END >-------------------------------------"
echo
${SETCOLOR_NORMAL}

read -p "请选择你的服务器网络环境[国外1/国内2]： " NETWORK
if [ ${NETWORK} == 1 ];then
    cd ${ORIGINAL} && git clone ${GITGPT}
elif [ ${NETWORK} == 2 ];then
    cd ${ORIGINAL} && git clone https://ghproxy.com/${GITGPT}
fi
${SETCOLOR_SUCCESS} && echo "-------------------------------------< END >-------------------------------------" && ${SETCOLOR_NORMAL}
}

function NODEJS() {
# 检查是否安装了Node.js
${SETCOLOR_SUCCESS} && echo "-------------------------------------<提 示>-------------------------------------" && ${SETCOLOR_NORMAL}
if ! command -v node &> /dev/null
then
    echo "Node.js 未安装，正在进行安装..."
    # 安装 Node.js
    curl -fsSL https://rpm.nodesource.com/setup_lts.x | sudo bash -
    yum install -y nodejs
else
    echo "Node.js 已安装..."
fi

# 检查是否安装了 pnpm
if ! command -v pnpm &> /dev/null
then
    echo "pnpm 未安装，正在进行安装..."
    # 安装 pnpm
    npm install -g pnpm
else
    echo "pnpm 已安装..." 
fi

${SETCOLOR_SUCCESS} && echo "-------------------------------------< END >-------------------------------------" && ${SETCOLOR_NORMAL}
}

function INFO() {
echo
${SETCOLOR_SUCCESS} && echo "-------------------------------------<提 示>-------------------------------------"
echo "                           构建之前请先指定Nginx根路径与.env文件!"
${SETCOLOR_SUCCESS}
${SETCOLOR_RED} && echo "                           注: 默认项目中的没有.env文件需要创建!"
${SETCOLOR_SUCCESS} && echo "-------------------------------------< END >-------------------------------------"
echo
${SETCOLOR_NORMAL}

# 交互输入Nginx根目录
read -p "请输入Nginx根目录(绝对路径)[不可缺失!]：" WEBDIR
if [ -z "${WEBDIR}" ];then
    ${SETCOLOR_RED} && echo "参数为空,退出执行"
    exit 1
else
    ${SETCOLOR_SUCCESS} && echo "Nginx根目录：${WEBDIR}" && ${SETCOLOR_NORMAL}
fi

read -p "修改用户默认名称/描述/头像信息,请用空格分隔[留空则保持默认!]：" USERINFO
if [ -z "${USERINFO}" ];then
    ${SETCOLOR_SKYBLUE} && echo "没有输入,保持默认" && ${SETCOLOR_NORMAL}
else
    USER=$(echo "${USERINFO}" | cut -d' ' -f1)
    INFO=$(echo "${USERINFO}" | cut -d' ' -f2)
    AVATAR=$(echo "${USERINFO}" | cut -d' ' -f3)
    ${SETCOLOR_SUCCESS} && echo "当前用户默认名称为：${USER}" && ${SETCOLOR_NORMAL}
    ${SETCOLOR_SUCCESS} && echo "当前描述信息默认为：${INFO}" && ${SETCOLOR_NORMAL}
    # 修改个人信息
    sed -i "s/ChenZhaoYu/${USER}/g" ${ORIGINAL}/${CHATDIR}/src/store/modules/user/helper.ts
    sed -i "s#Star on <a href=\"https://github.com/Chanzhaoyu/chatgpt-bot\" class=\"text-blue-500\" target=\"_blank\" >Github</a>#${INFO}#g" ${ORIGINAL}/${CHATDIR}/src/store/modules/user/helper.ts
    sed -i "s#https://raw.githubusercontent.com/Chanzhaoyu/chatgpt-web/main/src/assets/avatar.jpg#${AVATAR}#g" ${ORIGINAL}/${CHATDIR}/src/store/modules/user/helper.ts
fi
}

#前端
function BUILDWEB() {
# 安装依赖
pnpm bootstrap
# 打包
pnpm build
}
#后端
function BUILDSEV() {
# 安装依赖
pnpm install
# 打包
pnpm build
}


function BUILD() {
echo
${SETCOLOR_SUCCESS} && echo "-------------------------------------<提 示>-------------------------------------"
echo "                           开始进行构建.构建快慢取决于你的环境"
${SETCOLOR_SUCCESS}
${SETCOLOR_SUCCESS} && echo "-------------------------------------< END >-------------------------------------"
echo
${SETCOLOR_NORMAL}
# 拷贝.env配置替换
cp ${ORIGINAL}/env.example ${ORIGINAL}/${CHATDIR}/${SERDIR}/.env
echo
${SETCOLOR_SUCCESS} && echo "-----------------------------------<前端构建>-----------------------------------" && ${SETCOLOR_NORMAL}
# 前端
cd ${ORIGINAL}/${CHATDIR} && BUILDWEB
${SETCOLOR_SUCCESS} && echo "-------------------------------------< END >-------------------------------------" && ${SETCOLOR_NORMAL}
echo
echo
${SETCOLOR_SUCCESS} && echo "------------------------------------<后端构建>-----------------------------------" && ${SETCOLOR_NORMAL}
# 后端
cd ${SERDIR} && BUILDSEV
${SETCOLOR_SUCCESS} && echo "-------------------------------------< END >-------------------------------------" && ${SETCOLOR_NORMAL}
}

# 拷贝构建成品到Nginx网站根目录
function NGINX() {
# 拷贝后端并启动
${SETCOLOR_SUCCESS} && echo "-----------------------------------<后端部署>-----------------------------------" && ${SETCOLOR_NORMAL}
echo ${PWD}
\cp -fr ${ORIGINAL}/${CHATDIR}/${SERDIR} ${WEBDIR}
# 检查名为 node后端 的进程是否正在运行
pid=$(lsof -t -i:3002)
if [ -z "$pid" ]; then
    echo "后端程序未运行"
else
    echo "后端程序正在运行,现在停止程序并更新..."
    kill -9 $pid
fi
\cp -fr ${ORIGINAL}/${CHATDIR}/${FONTDIR}/* ${WEBDIR}
cd ${WEBDIR}/${SERDIR}  && nohup pnpm run start > app.log 2>&1 &
# 拷贝前端刷新Nginx服务
${SETCOLOR_SUCCESS} && echo "-----------------------------------<前端部署>-----------------------------------" && ${SETCOLOR_NORMAL}
if ! nginx -t ; then
    echo "Nginx 配置文件存在错误，请检查配置"
    exit 4
else
    nginx -s reload
fi
}

# 删除源码包文件
function DELSOURCE() {
  rm -rf ${ORIGINAL}/${CHATDIR}
  ${SETCOLOR_SUCCESS} && echo "-----------------------------------<部署完成>-----------------------------------" && ${SETCOLOR_NORMAL}
}

function main() {
   NODEJS
   GITCLONE
   INFO
   BUILD
   NGINX
   DELSOURCE
}
main
