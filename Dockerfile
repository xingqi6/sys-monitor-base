# 1. 官方镜像提取层 (获取 Uptime Kuma 核心文件)
FROM louislam/uptime-kuma:1 AS builder

# 2. 最终运行层 (改为 Debian 以解决 glibc 兼容性问题)
FROM debian:bullseye-slim

# 安装系统基础依赖
# 包含 python3-venv 以便后续创建虚拟环境
RUN apt-get update && \
    apt-get install -y python3 python3-pip python3-venv curl jq ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 创建伪装的工作目录
WORKDIR /usr/share/kernel_service

# 3. 核心文件“搬家”与“伪装”
# 将 node 二进制文件复制并重命名为 sys_kernel
COPY --from=builder /usr/local/bin/node /usr/local/bin/sys_kernel
# 将项目源码复制到伪装目录
COPY --from=builder /app /usr/share/kernel_service

# 4. 清理原有的 app 目录 (如果存在)
RUN rm -rf /app

# 5. 设置环境变量
ENV UPTIME_KUMA_PORT=3001
ENV DATA_DIR=/usr/share/kernel_service/sys_data
# 确保 node (sys_kernel) 能找到它的模块
ENV NODE_PATH=/usr/share/kernel_service/node_modules

# 6. 赋予可执行权限
RUN chmod +x /usr/local/bin/sys_kernel

# 默认入口 (仅供测试，实际会被 HF 的 boot.sh 覆盖)
ENTRYPOINT ["sys_kernel", "server/server.js"]
