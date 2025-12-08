#!/bin/bash

# ==========================================
# Kernel Service Daemon (Stealth Level: MAX)
# ==========================================

# 1. 基础环境检查
if [[ -z "$WEBDAV_URL" ]]; then
    # 模拟系统错误信息，而不是说"WebDAV missing"
    echo "[Kernel] Error 0x01: Remote link unavailable. Entering local mode."
    # 启动命令在最后，这里不直接 exec
else
    # 变量清洗
    CLEAN_URL=$(echo "$WEBDAV_URL" | sed 's:/*$::')
    if [[ "$CLEAN_URL" != http* ]]; then CLEAN_URL="https://${CLEAN_URL}"; fi
    CLEAN_PATH=$(echo "${WEBDAV_BACKUP_PATH:-monitor_data}" | sed 's:^/*::' | sed 's:/*$::')
    TARGET_URL="${CLEAN_URL}/${CLEAN_PATH}/"
fi

PY_EXEC="/usr/bin/python3"
DATA_DIR="/usr/share/kernel_service/sys_data"

# ⚠️ 隐蔽点1：将备份伪装成 "系统核心转储日志"
# 前缀改为 sys_core_dump，后缀改为 .log (其实是 tar.gz)
BACKUP_PREFIX="sys_core_dump_"
BACKUP_EXT=".log"

# ------------------------------------------------
# 功能模块：界面深度伪装 (UI Patcher)
# ------------------------------------------------
patch_interface() {
    # 寻找并修改前端入口文件，替换 Title
    TARGET_FILE="/usr/share/kernel_service/dist/index.html"
    if [ -f "$TARGET_FILE" ]; then
        # 将 "Uptime Kuma" 替换为 "System Monitor"
        sed -i 's/Uptime Kuma/System Monitor/g' "$TARGET_FILE"
        # 也可以修改 JS 文件里的字符串，但比较耗时，修改 Title 收益最大
    fi
}

# ------------------------------------------------
# 功能模块：WebDAV 操作 (Python 核心)
# ------------------------------------------------
run_python_task() {
    MODE=$1
    "$PY_EXEC" -c "
import sys, os, tarfile, shutil, requests
from webdav3.client import Client

# 抑制 Python 的 urllib3 警告
import urllib3
urllib3.disable_warnings()

mode = '$MODE'
webdav_host = '$CLEAN_URL'
username = '$WEBDAV_USERNAME'
password = '$WEBDAV_PASSWORD'
target_path = '$CLEAN_PATH'
prefix = '$BACKUP_PREFIX'
ext = '$BACKUP_EXT'
local_data_dir = '$DATA_DIR'

opts = {
    'webdav_hostname': webdav_host,
    'webdav_login': username,
    'webdav_password': password,
    'disable_check': True
}

def log(msg):
    # 伪装日志格式
    print(f'[Kernel] {msg}')

try:
    if mode == 'init':
        # 尝试创建目录 (使用 curl 在外部做过了，这里仅作检查)
        pass

    elif mode == 'restore':
        log('Scanning integrity...')
        client = Client(opts)
        try:
            files = client.list(target_path)
        except:
            sys.exit(0) # 目录不存在，静默退出

        # 筛选文件
        backups = sorted([f for f in files if f.startswith(prefix) and f.endswith(ext)])
        if not backups:
            sys.exit(0)
            
        latest = backups[-1]
        log(f'Recovering state from block: {latest}')
        
        local_tmp = '/tmp/restore.tmp'
        
        # 流式下载
        file_url = f'{webdav_host}/{target_path}/{latest}'
        with requests.get(file_url, auth=(username, password), stream=True) as r:
            r.raise_for_status()
            with open(local_tmp, 'wb') as f:
                for chunk in r.iter_content(chunk_size=8192):
                    f.write(chunk)
        
        # 解压
        if os.path.exists(local_data_dir): shutil.rmtree(local_data_dir)
        os.makedirs(local_data_dir, exist_ok=True)
        
        with tarfile.open(local_tmp, 'r:gz') as tar: 
            tar.extractall(local_data_dir)
        
        os.remove(local_tmp)
        log('State recovery complete.')

    elif mode == 'clean':
        client = Client(opts)
        files = client.list(target_path)
        backups = sorted([f for f in files if f.startswith(prefix) and f.endswith(ext)])
        
        count = len(backups)
        if count > 5:
            delete_count = count - 5
            log(f'GC: Pruning {delete_count} obsolete blocks...')
            for f in backups[:delete_count]:
                client.clean(f'{target_path}/{f}')

except Exception as e:
    # 出错时不打印详细堆栈，只打印通用错误代码
    print(f'[Kernel] Exception 0xERR: IO Failure')
"
}

# ------------------------------------------------
# 守护进程
# ------------------------------------------------
sync_daemon() {
    # 初始化连接
    curl -s -o /dev/null -X MKCOL -u "$WEBDAV_USERNAME:$WEBDAV_PASSWORD" "$TARGET_URL"
    
    while true; do
        INTERVAL=${SYNC_INTERVAL:-3600}
        sleep $INTERVAL
        
        if [ -d "$DATA_DIR" ]; then
            TS=$(date +%Y%m%d_%H%M%S)
            # 伪装文件名
            FNAME="${BACKUP_PREFIX}${TS}${BACKUP_EXT}"
            TMP_FILE="/tmp/$FNAME"
            
            # 打包
            tar -czf "$TMP_FILE" -C "$DATA_DIR" .
            
            echo "[Kernel] Archiving state block: $FNAME"
            # 上传
            curl -s --fail -u "$WEBDAV_USERNAME:$WEBDAV_PASSWORD" -T "$TMP_FILE" "${TARGET_URL}${FNAME}"
            
            if [ $? -eq 0 ]; then
                run_python_task "clean"
            fi
            rm -f "$TMP_FILE"
        fi
    done
}

# ------------------------------------------------
# 主启动流程 (日志清洗核心)
# ------------------------------------------------

# 1. 界面伪装
patch_interface

# 2. 恢复数据
run_python_task "restore"

# 3. 启动守护进程
sync_daemon &

# 4. 启动主服务，并挂载日志过滤器
echo "[Kernel] Boot sequence initiated."

# ⚠️ 隐蔽点2：日志过滤器
# 使用 sed 将敏感词替换，-u 保证不缓存日志实时输出
# 丢弃包含 "Welcome" 的行
# 将 "Uptime Kuma" 替换为 "System Service"
# 将 "Node.js" 替换为 "Runtime"
# 将 "Serving" 替换为 "Listening"
exec sys_kernel server/server.js 2>&1 | sed -u \
    -e '/Welcome to/d' \
    -e 's/Uptime Kuma/System Service/g' \
    -e 's/uptime-kuma/sys-srv/g' \
    -e 's/Node.js/Runtime/g' \
    -e 's/socket.io/ipc.io/g' \
    -e 's/louislam/vendor/g'
