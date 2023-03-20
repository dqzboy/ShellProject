## 脚本执行操作流程演示
- **说明**：目前该脚本只适用于CentOS 7系统
- 下载仓库下面的`env.example`示例文件，并与脚本文件存放在同级目录下，执行脚本前记得修改文件里的相关参数，例如API KEY等信息
- **注意**：如果服务器已经安装了Nginx，那么构建之前请指定ChatGPT-WEB前端项目存放的Nginx根路径
```shell
[root@localhost ~]# mkdir -p /data/chatgpt-web 
[root@localhost ~]# cd /data/chatgpt-web
[root@localhost chatgpt-web]# ls
chatGPT-WEB_build.sh  env.example

[root@localhost chatgpt-web]# chmod +x chatGPT-WEB_build.sh 
[root@localhost chatgpt-web]# ./chatGPT-WEB_build.sh
```
<table>
    <tr>
        <td width="50%" align="center"><img src="https://user-images.githubusercontent.com/42825450/226394338-a9ab319d-f732-4f77-8484-06ffbc56fe08.png"?raw=true"></td>
        <td width="50%" align="center"><img src=""?raw=true"></td>
    </tr>
</table>




## Nginx后端接口配置参考
- 需要在server块中添加一个location规则用来代理后端API接口地址，配置修改参考如下：

> /etc/nginx/conf.d/default.conf
```shell
server {
    listen       80;
    server_name  localhost;

    #access_log  /var/log/nginx/host.access.log  main;

    location / {
        root   /usr/share/nginx/html;
        index  index.html index.htm;
    }

    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
        root   /usr/share/nginx/html;
    }


    location /api/ {
        # 处理 Node.js 后端 API 的请求
        proxy_pass http://localhost:3002;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;        
        proxy_set_header X-Nginx-Proxy true;
        proxy_buffering off;
        proxy_redirect off;
    }
}
```
