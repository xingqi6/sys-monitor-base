# 1. 提取核心文件
FROM louislam/uptime-kuma:1 AS builder

# 2. 构建运行环境 (Debian 11 Bullseye)
FROM debian:bullseye-slim

# 安装系统依赖和 Python 库
# ⚠️ 修正：删除了 --break-system-packages，因为 Bullseye 不需要且不支持它
RUN apt-get update && \
    apt-get install -y python3 python3-pip curl jq ca-certificates && \
    pip3 install --no-cache-dir requests webdavclient3 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 伪装工作目录
WORKDIR /usr/share/kernel_service

# 复制核心文件
COPY --from=builder /usr/local/bin/node /usr/local/bin/sys_kernel
COPY --from=builder /app /usr/share/kernel_service

# 复制 boot.sh 并赋权
COPY boot.sh /usr/share/kernel_service/boot.sh
RUN chmod +x /usr/share/kernel_service/boot.sh

# 清理旧目录
RUN rm -rf /app

# 环境变量
ENV UPTIME_KUMA_PORT=3001
ENV DATA_DIR=/usr/share/kernel_service/sys_data
ENV NODE_PATH=/usr/share/kernel_service/node_modules

# 赋予 sys_kernel 权限
RUN chmod +x /usr/local/bin/sys_kernel

# 设置入口点
ENTRYPOINT ["/usr/share/kernel_service/boot.sh"]
