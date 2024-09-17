#!/bin/bash

# 获取所有构建器的详细信息
BUILDERS_INFO=$(docker buildx ls)

# 获取当前使用的构建器（带星号的）
CURRENT_BUILDER=$(echo "$BUILDERS_INFO" | awk '/\*/ {gsub(/\*$/, "", $1); print $1}')

echo "当前使用的构建器: $CURRENT_BUILDER"
echo "开始清理构建器..."

# 初始化数组来存储保留和删除的构建器
RETAINED_BUILDERS=()
DELETED_BUILDERS=()

# 使用 while 循环读取每一行，这样可以正确处理多行输出
while IFS= read -r line; do
    # 跳过标题行和空行
    if [[ $line =~ NAME || $line =~ --- || -z $line ]]; then
        continue
    fi

    # 提取构建器名称和状态
    BUILDER=$(echo "$line" | awk '{print $1}')
    STATUS=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if($i=="running" || $i=="inactive" || $i=="stopped") print $i; exit}')

    # 移除构建器名称中的星号（如果有）
    BUILDER=${BUILDER%\*}

    # 如果是子节点（以 "\_" 开头），跳过
    if [[ $BUILDER == \\_* ]]; then
        continue
    fi

    # 判断是否需要保留此构建器
    if [[ "$BUILDER" == "$CURRENT_BUILDER" || "$BUILDER" == "default" || "$STATUS" == "running" ]]; then
        RETAINED_BUILDERS+=("$BUILDER")
    else
        DELETED_BUILDERS+=("$BUILDER")
        docker buildx rm -f "$BUILDER" > /dev/null 2>&1
    fi
done <<< "$BUILDERS_INFO"

# 显示删除的构建器
if [ ${#DELETED_BUILDERS[@]} -eq 0 ]; then
    echo "删除的构建器: 无"
else
    echo "删除的构建器: ${DELETED_BUILDERS[*]}"
fi

# 显示保留的构建器
if [ ${#RETAINED_BUILDERS[@]} -eq 0 ]; then
    echo "保留的构建器: 无"
else
    echo "保留的构建器: ${RETAINED_BUILDERS[*]}"
fi

echo "清理完成"
echo "当前构建器列表:"
# 获取并显示当前构建器列表（只包含名称和状态）
docker buildx ls --format '{{.Name}}\t{{.Status}}' | while read -r name status; do
    if [[ -n $status ]]; then
        echo "- $name (状态: $status)"
    fi
done
