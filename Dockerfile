# 1. 提取层
FROM louislam/uptime-kuma:1 AS builder

# 2. 最终层 - 改用 Debian Slim 以解决 glibc 兼容性问题
FROM debian:bullseye-slim

# 安装基础依赖 (apt源)
RUN apt-get update && \
    apt-get install -y python3 python3-pip python3-venv curl jq netcat && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 创建伪装目录
WORKDIR /usr/share/kernel_service

# 复制核心文件
COPY --from=builder /usr/local/bin/node /usr/local/bin/sys_kernel
COPY --from=builder /app /usr/share/kernel_service

# 清理与设置
RUN rm -rf /app
ENV UPTIME_KUMA_PORT=3001
ENV DATA_DIR=/usr/share/kernel_service/sys_data

# 赋权
RUN chmod +x /usr/local/bin/sys_kernel

# 默认入口
ENTRYPOINT ["sys_kernel", "server/server.js"]
