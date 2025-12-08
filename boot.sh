#!/bin/bash

# ==========================================
# System Kernel Watchdog (Fixed: Robust Restore)
# ==========================================

if [[ -z "$WEBDAV_URL" ]]; then
    echo "[Kernel] No WebDAV URL. Starting local mode."
    exec sys_kernel server/server.js
fi

# ---------------- 1. 变量清洗 ----------------
CLEAN_URL=$(echo "$WEBDAV_URL" | sed 's:/*$::')
if [[ "$CLEAN_URL" != http* ]]; then CLEAN_URL="https://${CLEAN_URL}"; fi
CLEAN_PATH=$(echo "${WEBDAV_BACKUP_PATH:-monitor_data}" | sed 's:^/*::' | sed 's:/*$::')
TARGET_URL="${CLEAN_URL}/${CLEAN_PATH}/"

# ⚠️ 全局 Python 路径
PY_EXEC="/usr/bin/python3"
DATA_DIR="/usr/share/kernel_service/sys_data"
BACKUP_PREFIX="kuma_state_"

# ---------------- 2. 初始化检查 ----------------
init_remote() {
    echo "[Kernel] Initializing storage connection..."
    curl -s -o /dev/null -X MKCOL -u "$WEBDAV_USERNAME:$WEBDAV_PASSWORD" "$TARGET_URL"
}

# ---------------- 3. 自动清理函数 ----------------
rotate_backups() {
    "$PY_EXEC" -c "
from webdav3.client import Client
import os

opts = {
    'webdav_hostname': '$CLEAN_URL',
    'webdav_login': '$WEBDAV_USERNAME',
    'webdav_password': '$WEBDAV_PASSWORD',
    'disable_check': True
}
target_path = '$CLEAN_PATH'
prefix = '$BACKUP_PREFIX'

try:
    client = Client(opts)
    files = client.list(target_path)
    backups = sorted([f for f in files if f.startswith(prefix) and f.endswith('.tar.gz')])
    
    count = len(backups)
    if count > 5:
        delete_count = count - 5
        print(f'[Kernel] Maintenance: Found {count} backups. Cleaning {delete_count} old files...')
        for f in backups[:delete_count]:
            client.clean(f'{target_path}/{f}')
            print(f'[Kernel] Deleted old snapshot: {f}')
    else:
        print(f'[Kernel] Maintenance: {count}/5 snapshots. Storage healthy.')
except Exception as e:
    print(f'[Kernel] Maintenance Warning: {str(e)}')
"
}

# ---------------- 4. 核心恢复函数 (修复版: 使用 requests 流式下载) ----------------
restore_data() {
    echo "[Kernel] Checking for backups to restore..."
    "$PY_EXEC" -c "
import sys, os, tarfile, shutil, requests
from webdav3.client import Client

# 配置
webdav_host = '$CLEAN_URL'
username = '$WEBDAV_USERNAME'
password = '$WEBDAV_PASSWORD'
target_path = '$CLEAN_PATH'
prefix = '$BACKUP_PREFIX'
local_data_dir = '$DATA_DIR'

# WebDAV Client 仅用于获取文件列表
opts = {
    'webdav_hostname': webdav_host,
    'webdav_login': username,
    'webdav_password': password,
    'disable_check': True
}

try:
    client = Client(opts)
    try:
        files = client.list(target_path)
    except:
        print('[Kernel] Remote folder not found. Starting fresh.')
        sys.exit(0)

    backups = sorted([f for f in files if f.startswith(prefix) and f.endswith('.tar.gz')])
    if not backups:
        print('[Kernel] No valid backup found. Starting fresh.')
        sys.exit(0)
        
    latest = backups[-1]
    print(f'[Kernel] Found latest snapshot: {latest}')
    print(f'[Kernel] Downloading via Stream...')
    
    local_tmp = '/tmp/restore.tar.gz'
    
    # 修复点：改用 requests 原生下载，不依赖 Content-Length
    file_url = f'{webdav_host}/{target_path}/{latest}'
    with requests.get(file_url, auth=(username, password), stream=True) as r:
        r.raise_for_status()
        with open(local_tmp, 'wb') as f:
            for chunk in r.iter_content(chunk_size=8192):
                f.write(chunk)
            
    # 解压
    if os.path.exists(local_data_dir):
        shutil.rmtree(local_data_dir)
    os.makedirs(local_data_dir, exist_ok=True)
    
    with tarfile.open(local_tmp, 'r:gz') as tar: 
        tar.extractall(local_data_dir)
    print('[Kernel] Restore successful!')
    os.remove(local_tmp)

except Exception as e:
    print(f'[Kernel] Restore Critical Error: {str(e)}')
    # 即使失败也允许启动，避免 Space 崩溃
"
}

# ---------------- 5. 守护进程 ----------------
sync_daemon() {
    init_remote
    while true; do
        INTERVAL=${SYNC_INTERVAL:-3600}
        sleep $INTERVAL
        if [ -d "$DATA_DIR" ]; then
            TS=$(date +%Y%m%d_%H%M%S)
            FNAME="${BACKUP_PREFIX}${TS}.tar.gz"
            TMP_FILE="/tmp/$FNAME"
            tar -czf "$TMP_FILE" -C "$DATA_DIR" .
            echo "[Kernel] Uploading snapshot: $FNAME ..."
            curl -s --fail -u "$WEBDAV_USERNAME:$WEBDAV_PASSWORD" -T "$TMP_FILE" "${TARGET_URL}${FNAME}"
            if [ $? -eq 0 ]; then
                echo "[Kernel] ✅ Upload success."
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
restore_data
sync_daemon &
echo "[Kernel] Daemon active. Service launched."
exec sys_kernel server/server.js
