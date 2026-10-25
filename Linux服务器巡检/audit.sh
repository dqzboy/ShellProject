#!/usr/bin/env bash
echo "===== 系统概况 ====="
uname -srm; echo "CPU 核数: $(nproc)"; free -h; uptime
echo
echo "===== 运行中的服务 ====="
systemctl list-units --type=service --state=running --no-legend --plain | awk '{print $1}'
echo
echo "===== 监听端口 ====="
ss -tulpn | grep LISTEN
echo
echo "===== 内存 TOP 10 ====="
ps -eo pid,user,%cpu,%mem,rss,comm --sort=-%mem | head -11
echo
echo "===== CPU TOP 10 ====="
ps -eo pid,user,%cpu,%mem,rss,comm --sort=-%cpu | head -11
echo
echo "===== Docker 容器 ====="
command -v docker >/dev/null && docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" || echo "(未安装)"
echo
echo "===== 定时任务 ====="
crontab -l 2>/dev/null || echo "(root 无 crontab)"
ls /etc/cron.d/ 2>/dev/null
echo
echo "===== 开机自启 ====="
systemctl list-unit-files --state=enabled --no-legend | head -30
echo
echo "===== 最近 OOM ====="
dmesg -T 2>/dev/null | grep -iE "out of memory|killed process" | tail -5 || echo "(无)"
