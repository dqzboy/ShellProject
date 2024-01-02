#!/usr/bin/env bash
#===============================================================================
#
#          FILE: manage_cron_tasks.sh
# 
#         USAGE: ./manage_cron_tasks.sh
# 
#   DESCRIPTION: 管理系统上所有用户的定时任务。通过选择是否删除每个用户的定时任务
# 
#  ORGANIZATION: dqzboy.com
#       CREATED: 2022
#===============================================================================

# 获取所有用户列表
user_list=$(cut -d: -f1 /etc/passwd)

# 初始化标志变量，用于判断是否有用户有定时任务
has_cron_tasks=false

# 遍历用户列表
for user in $user_list
do
    # 查看用户的cron任务
    cron_tasks=$(crontab -u $user -l 2>/dev/null)
    
    # 如果用户有定时任务
    if [ -n "$cron_tasks" ]; then
        has_cron_tasks=true
        echo "User: $user"
        echo "Cron Tasks:"
        echo "$cron_tasks"
        echo "====================="
        
        # 询问用户是否删除该用户的定时任务
        read -p "Do you want to delete cron tasks for $user? (y/n): " delete_choice
        if [ "$delete_choice" == "y" ]; then
            # 询问用户删除第几条或全部
            read -p "Enter the task number(s) to delete (e.g., 1 3 5 for specific tasks, a for all tasks): " task_numbers
            if [ "$task_numbers" == "a" ]; then
                # 删除所有定时任务
                crontab -r -u $user
                echo "All cron tasks deleted for $user."
            else
                # 备份用户的原始定时任务
                original_cron_tasks=$(mktemp)
                crontab -u $user -l > "$original_cron_tasks"

                # 删除指定定时任务
                for task_number in $task_numbers
                do
                    sed -i "${task_number}d" "$original_cron_tasks"
                done

                # 恢复修改后的定时任务
                crontab -u $user "$original_cron_tasks"
                rm "$original_cron_tasks"
                echo "Selected cron tasks deleted for $user."
            fi
        fi
    fi
done

# 如果所有用户都没有定时任务，则打印提示信息
if [ "$has_cron_tasks" == false ]; then
    echo "No cron tasks found for any user."
fi
