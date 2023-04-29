#!/bin/bash

# 设置要保留的日志时间（以天为单位）
LOG_RETENTION_DAYS=7

# 清理systemd管理的服务日志
sudo journalctl --vacuum-time=${LOG_RETENTION_DAYS}d

# 重启systemd-journald服务以使更改生效
sudo systemctl restart systemd-journald
