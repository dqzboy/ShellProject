#!/bin/bash

# 显示欢迎信息
echo "================================================"
echo "Cursor 重置工具"
echo "此脚本将重置 Cursor 应用的标识信息以恢复试用期"
echo "================================================"
echo ""
echo "步骤 1/7: 准备工作..."

# 获取实际用户信息
if [ -n "$SUDO_USER" ]; then
    REAL_USER="$SUDO_USER"
elif [ -n "$DOAS_USER" ]; then
    REAL_USER="$DOAS_USER"
else
    REAL_USER=$(who am i | awk '{print $1}')
    if [ -z "$REAL_USER" ]; then
        REAL_USER=$(logname)
    fi
fi

if [ -z "$REAL_USER" ]; then
    echo "❌ 错误: 无法确定实际用户"
    exit 1
fi

REAL_HOME=$(eval echo ~$REAL_USER)
echo "✅ 已确定用户: $REAL_USER"
echo "✅ 用户主目录: $REAL_HOME"

# 检查必要的命令
echo "正在检查所需工具..."
for cmd in uuidgen ioreg; do
    if ! command -v $cmd &> /dev/null; then
        echo "❌ 错误: 需要 $cmd 但未找到"
        exit 1
    else
        echo "✓ $cmd 已找到"
    fi
done
echo "✅ 所有必需工具已就绪"
echo ""

# 生成类似 macMachineId 的格式
generate_mac_machine_id() {
    # 使用 uuidgen 生成基础 UUID，然后确保第 13 位是 4，第 17 位是 8-b
    uuid=$(uuidgen | tr '[:upper:]' '[:lower:]')
    # 确保第 13 位是 4
    uuid=$(echo $uuid | sed 's/.\{12\}\(.\)/4/')
    # 确保第 17 位是 8-b (通过随机数)
    random_hex=$(echo $RANDOM | md5 | cut -c1)
    random_num=$((16#$random_hex))
    new_char=$(printf '%x' $(( ($random_num & 0x3) | 0x8 )))
    uuid=$(echo $uuid | sed "s/.\{16\}\(.\)/$new_char/")
    echo $uuid
}

# 生成64位随机ID
generate_random_id() {
    uuid1=$(uuidgen | tr -d '-')
    uuid2=$(uuidgen | tr -d '-')
    echo "${uuid1}${uuid2}"
}

# 检查 Cursor 进程并显示PID
check_cursor_process() {
    echo "正在检查 Cursor 进程状态..."
    cursor_pids=$(pgrep -x "Cursor" 2>/dev/null)
    cursor_app_pids=$(pgrep -f "Cursor.app" 2>/dev/null)
    
    if [ -n "$cursor_pids" ] || [ -n "$cursor_app_pids" ]; then
        echo "⚠️ 检测到 Cursor 正在运行，进程 PID 如下:"
        
        if [ -n "$cursor_pids" ]; then
            echo "  Cursor 进程: $cursor_pids"
        fi
        
        if [ -n "$cursor_app_pids" ]; then
            # 过滤掉与cursor_pids重复的PID
            for pid in $cursor_app_pids; do
                if ! echo "$cursor_pids" | grep -q "$pid"; then
                    echo "  Cursor.app 相关进程: $pid ($(ps -p $pid -o comm= 2>/dev/null))"
                fi
            done
        fi
        
        # 合并所有PID
        all_pids="$cursor_pids $cursor_app_pids"
        
        # 用户选择
        read -p "是否要终止这些进程以继续? (y/n): " choice
        case "$choice" in
            [Yy]*)
                echo "正在终止 Cursor 进程..."
                for pid in $all_pids; do
                    kill -15 $pid 2>/dev/null
                done
                echo "  等待进程结束..."
                sleep 2
                
                # 检查是否还有顽固进程
                remaining_pids=$(pgrep -x "Cursor" 2>/dev/null)
                remaining_app_pids=$(pgrep -f "Cursor.app" 2>/dev/null)
                
                if [ -n "$remaining_pids" ] || [ -n "$remaining_app_pids" ]; then
                    echo "  某些进程未能正常终止，尝试强制终止..."
                    for pid in $remaining_pids $remaining_app_pids; do
                        kill -9 $pid 2>/dev/null
                    done
                    sleep 1
                fi
                
                echo "✅ 所有 Cursor 进程已终止"
                return 0
                ;;
            *)
                echo "❌ 操作已取消。请先手动关闭 Cursor 再运行脚本。"
                exit 1
                ;;
        esac
    else
        echo "✅ Cursor 未在运行"
    fi
    
    return 0
}

# 定义文件路径
STORAGE_JSON="$REAL_HOME/Library/Application Support/Cursor/User/globalStorage/storage.json"
FILES=(
    "/Applications/Cursor.app/Contents/Resources/app/out/main.js"
    "/Applications/Cursor.app/Contents/Resources/app/out/vs/code/node/cliProcessMain.js"
)

# 调用检查函数
echo "步骤 2/7: 检查并关闭 Cursor 应用..."
check_cursor_process
echo "✅ Cursor 已关闭，继续执行..."
echo ""

echo "步骤 3/7: 更新标识信息..."
# 更新 storage.json
NEW_MACHINE_ID=$(generate_random_id)
NEW_MAC_MACHINE_ID=$(generate_mac_machine_id)
NEW_DEV_DEVICE_ID=$(uuidgen)
NEW_SQM_ID="{$(uuidgen | tr '[:lower:]' '[:upper:]')}"

if [ -f "$STORAGE_JSON" ]; then
    echo "  正在备份并更新配置文件..."
    # 备份原始文件
    cp "$STORAGE_JSON" "${STORAGE_JSON}.bak" || {
        echo "❌ 错误: 无法备份 storage.json"
        exit 1
    }
    
    # 确保备份文件的所有权正确
    chown $REAL_USER:staff "${STORAGE_JSON}.bak"
    chmod 644 "${STORAGE_JSON}.bak"
    
    # 使用 osascript 更新 JSON 文件
    osascript -l JavaScript << EOF
        function run() {
            const fs = $.NSFileManager.defaultManager;
            const path = '$STORAGE_JSON';
            const nsdata = fs.contentsAtPath(path);
            const nsstr = $.NSString.alloc.initWithDataEncoding(nsdata, $.NSUTF8StringEncoding);
            const content = nsstr.js;
            const data = JSON.parse(content);
            
            data['telemetry.machineId'] = '$NEW_MACHINE_ID';
            data['telemetry.macMachineId'] = '$NEW_MAC_MACHINE_ID';
            data['telemetry.devDeviceId'] = '$NEW_DEV_DEVICE_ID';
            data['telemetry.sqmId'] = '$NEW_SQM_ID';
            
            const newContent = JSON.stringify(data, null, 2);
            const newData = $.NSString.alloc.initWithUTF8String(newContent);
            newData.writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null);
            
            return "success";
        }
EOF
    
    if [ $? -ne 0 ]; then
        echo "❌ 错误: 更新 storage.json 失败"
        exit 1
    fi

    # 确保修改后的文件所有权正确
    chown $REAL_USER:staff "$STORAGE_JSON"
    chmod 644 "$STORAGE_JSON"
fi

echo "✅ 成功更新所有标识信息:"
echo "  • 备份文件已创建于: ${STORAGE_JSON}.bak"
echo "  • 新 machineId: $NEW_MACHINE_ID"
echo "  • 新 macMachineId: $NEW_MAC_MACHINE_ID"
echo "  • 新 devDeviceId: $NEW_DEV_DEVICE_ID"
echo "  • 新 sqmId: $NEW_SQM_ID"
echo ""

echo "步骤 4/7: 复制应用到临时目录..."
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TEMP_DIR="/tmp/cursor_reset_${TIMESTAMP}"
TEMP_APP="$TEMP_DIR/Cursor.app"

# 确保临时目录不存在
if [ -d "$TEMP_DIR" ]; then
    echo "  清理已存在的临时目录..."
    rm -rf "$TEMP_DIR"
fi

# 创建临时目录
mkdir -p "$TEMP_DIR" || {
    echo "❌ 错误: 无法创建临时目录"
    exit 1
}

# 复制应用到临时目录
echo "  开始复制应用(这可能需要几分钟)..."
cp -R "/Applications/Cursor.app" "$TEMP_DIR" || {
    echo "❌ 错误: 无法复制应用到临时目录"
    rm -rf "$TEMP_DIR"
    exit 1
}

# 确保临时目录的权限正确
chown -R $REAL_USER:staff "$TEMP_DIR"
chmod -R 755 "$TEMP_DIR"
echo "✅ 应用已成功复制到临时目录"
echo ""

echo "步骤 5/7: 移除应用签名..."
codesign --remove-signature "$TEMP_APP" || {
    echo "⚠️ 警告: 移除应用签名失败，将继续执行"
}

# 移除所有相关组件的签名
components=(
    "$TEMP_APP/Contents/Frameworks/Cursor Helper.app"
    "$TEMP_APP/Contents/Frameworks/Cursor Helper (GPU).app"
    "$TEMP_APP/Contents/Frameworks/Cursor Helper (Plugin).app"
    "$TEMP_APP/Contents/Frameworks/Cursor Helper (Renderer).app"
)

for component in "${components[@]}"; do
    if [ -e "$component" ]; then
        echo "  移除签名: $(basename "$component")"
        codesign --remove-signature "$component" || {
            echo "  ⚠️ 警告: 移除组件签名失败: $(basename "$component")"
        }
    fi
done
echo "✅ 应用签名移除完成"
echo ""

echo "步骤 6/7: 修改应用核心文件..."
# 修改临时应用中的文件
FILES=(
    "$TEMP_APP/Contents/Resources/app/out/main.js"
    "$TEMP_APP/Contents/Resources/app/out/vs/code/node/cliProcessMain.js"
)

# 处理每个文件
for file in "${FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "⚠️ 警告: 文件 $(basename "$file") 不存在"
        continue
    fi

    echo "  正在修改: $(basename "$file")"
    # 创建备份
    backup_file="${file}.bak"
    cp "$file" "$backup_file" || {
        echo "❌ 错误: 无法备份文件 $(basename "$file")"
        continue
    }

    # 读取文件内容
    content=$(cat "$file")
    
    # 查找 IOPlatformUUID 的位置
    uuid_pos=$(printf "%s" "$content" | grep -b -o "IOPlatformUUID" | cut -d: -f1)
    if [ -z "$uuid_pos" ]; then
        echo "⚠️ 警告: 在 $(basename "$file") 中未找到 IOPlatformUUID"
        continue
    fi

    # 从 UUID 位置向前查找 switch
    before_uuid=${content:0:$uuid_pos}
    switch_pos=$(printf "%s" "$before_uuid" | grep -b -o "switch" | tail -n1 | cut -d: -f1)
    if [ -z "$switch_pos" ]; then
        echo "⚠️ 警告: 在 $(basename "$file") 中未找到 switch 关键字"
        continue
    fi

    # 构建新的文件内容
    printf "%sreturn crypto.randomUUID();\n%s" "${content:0:$switch_pos}" "${content:$switch_pos}" > "$file" || {
        echo "❌ 错误: 无法写入文件 $(basename "$file")"
        continue
    }

    echo "  ✓ 成功修改文件: $(basename "$file")"
done

# 重新签名临时应用
echo "  正在重新签名临时应用..."
codesign --sign - "$TEMP_APP" --force --deep || {
    echo "⚠️ 警告: 重新签名失败，应用可能需要在首次启动时授权"
}

echo "✅ 核心文件修改完成"
echo ""

echo "步骤 7/7: 安装修改后的应用..."
# 关闭原应用
echo "  确保 Cursor 已关闭..."
osascript -e 'tell application "Cursor" to quit' || true
sleep 2

# 直接替换原应用
echo "  安装修改后的应用..."
sudo rm -rf "/Applications/Cursor.app" || {
    echo "❌ 错误: 无法删除原应用，请确保以 sudo 方式运行此脚本"
    rm -rf "$TEMP_DIR"
    exit 1
}

# 移动修改后的应用到应用程序文件夹
sudo mv "$TEMP_APP" "/Applications/" || {
    echo "❌ 错误: 无法安装修改后的应用"
    rm -rf "$TEMP_DIR"
    exit 1
}
echo "✅ 修改后的应用已成功安装"
echo ""

echo "步骤 7/7: 清理临时文件..."
# 清理临时目录
rm -rf "$TEMP_DIR"
echo "✅ 临时文件已清理"
echo ""

echo "================================================"
echo "✅ Cursor 重置完成！"
echo "  • 标识信息已更新，试用期已重置"
echo "================================================"
echo "现在可以启动 Cursor 尝试了！"
