## 介绍

结合开源项目[LLM-Red-Team](https://github.com/LLM-Red-Team) 一键部署国内大模型

## 教程
1、下载本仓库下面的`docker-compose.yml`文件到指定目录下，例如：`/data/llm-red-team/docker-compose.yml`

2、下载本仓库下面的`manage_llm_docker.sh`文件存储到指定目录下,记得修改脚本中的COMPOSE_FILE变量为你实际`docker-compose.yml`文件存储的路径

3、赋予脚本执行权限并执行
```
chmod +x manage_llm_docker.sh
./manage_llm_docker.sh
```
![image](https://github.com/user-attachments/assets/8d65f62f-f2d6-49cb-bd60-7fbb3a66ecdd)
