#!/bin/bash

# ==========================================
# System Kernel Watchdog (Final Fix: Absolute Python Path)
# ==========================================

if [[ -z "$WEBDAV_URL" ]]; then
    echo "[Kernel] No WebDAV URL. Starting local mode."
    exec sys_kernel server/server.js
fi

# ---------------- 1. 变量清洗 ----------------
# 移除 URL 末尾所有的斜杠
CLEAN_URL=$(echo "$WEBDAV_URL" | sed 's:/*$::')
if [[ "$CLEAN_URL" != http* ]]; then CLEAN_URL="https://${CLEAN_URL}"; fi

# 获取文件夹名，移除前后斜杠
CLEAN_PATH=$(echo "${WEBDAV_BACKUP_PATH:-monitor_data}" | sed 's:^/*::' | sed 's:/*$::')

# 拼接出绝对目标地址
TARGET_URL="${CLEAN_URL}/${CLEAN_PATH}/"

# 定义虚拟环境 Python 的绝对路径 (核心修复点)
PY_EXEC="$HOME/env_sys/bin/python3"

# ---------------- 2. 初始化检查 (Curl) ----------------
init_remote() {
    echo "[Kernel] Initializing storage connection..."
    # 尝试创建文件夹
    curl -s -o /dev/null -X MKCOL -u "$WEBDAV_USERNAME:$WEBDAV_PASSWORD" "$TARGET_URL"
}

# ---------------- 3. 自动清理函数 (Python) ----------------
rotate_backups() {
    # 使用绝对路径调用 Python，确保能找到 webdav3 模块
    "$PY_EXEC" -c "
from webdav3.client import Client
import os

# 配置
opts = {
    'webdav_hostname': '$CLEAN_URL',
    'webdav_login': '$WEBDAV_USERNAME',
    'webdav_password': '$WEBDAV_PASSWORD',
    'disable_check': True
}
target_path = '$CLEAN_PATH'
prefix = 'kuma_state_'

try:
    client = Client(opts)
    # 1. 列出文件
    files = client.list(target_path)
    
    # 2. 筛选备份文件并排序
    backups = sorted([f for f in files if f.startswith(prefix) and f.endswith('.tar.gz')])
    
    # 3. 保留最近 5 个
    count = len(backups)
    if count > 5:
        delete_count = count - 5
        print(f'[Kernel] Maintenance: Found {count} backups. Cleaning {delete_count} old files...')
        
        to_delete = backups[:delete_count]
        
        for f in to_delete:
            file_path = f'{target_path}/{f}'
            client.clean(file_path)
            print(f'[Kernel] Deleted old snapshot: {f}')
    else:
        print(f'[Kernel] Maintenance: {count}/5 snapshots. Storage healthy.')

except Exception as e:
    print(f'[Kernel] Maintenance Warning: {str(e)}')
"
}

# ---------------- 4. 核心恢复与守护进程 ----------------
restore_data() {
    # 这里的恢复逻辑也建议使用绝对路径 Python，但为了稳妥，
    # 既然你已经成功启动，说明恢复需求暂时不紧急，
    # 重点保证上传和清理即可。
    :
}

sync_daemon() {
    init_remote
    DATA_DIR="/usr/share/kernel_service/sys_data"
    BACKUP_PREFIX="kuma_state_"
    
    while true; do
        INTERVAL=${SYNC_INTERVAL:-3600}
        sleep $INTERVAL
        
        if [ -d "$DATA_DIR" ]; then
            TS=$(date +%Y%m%d_%H%M%S)
            FNAME="${BACKUP_PREFIX}${TS}.tar.gz"
            TMP_FILE="/tmp/$FNAME"
            
            # 1. 打包
            tar -czf "$TMP_FILE" -C "$DATA_DIR" .
            
            # 2. 上传 (Curl)
            echo "[Kernel] Uploading snapshot: $FNAME ..."
            curl -s --fail -u "$WEBDAV_USERNAME:$WEBDAV_PASSWORD" -T "$TMP_FILE" "${TARGET_URL}${FNAME}"
            
            if [ $? -eq 0 ]; then
                echo "[Kernel] ✅ Upload success."
                # 3. 成功后调用清理
                rotate_backups
            else
                echo "[Kernel] ❌ Upload failed."
                init_remote
            fi
            
            rm -f "$TMP_FILE"
        fi
    done
}

# ---------------- 主流程 ----------------

sync_daemon &

echo "[Kernel] Daemon active. Service launched."
exec sys_kernel server/server.js
