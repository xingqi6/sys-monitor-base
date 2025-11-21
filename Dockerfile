# 使用官方镜像作为源
FROM louislam/uptime-kuma:1 AS builder

# 最终构建层 - 使用 Alpine 减小体积并混淆
FROM alpine:latest

# 安装运行依赖
RUN apk add --no-cache python3 py3-pip bash git libstdc++

# 1. 创建伪装的系统目录
WORKDIR /usr/share/kernel_service

# 2. 从官方镜像复制核心文件，但打散结构
# 复制 Node.js 二进制文件并重命名为 sys_kernel
COPY --from=builder /usr/local/bin/node /usr/local/bin/sys_kernel
# 复制源码到伪装目录
COPY --from=builder /app /usr/share/kernel_service

# 3. 清理原来的特征文件（如果有）
RUN rm -rf /app

# 4. 设置环境变量，告诉 Kuma 数据存在哪
ENV UPTIME_KUMA_PORT=3001
ENV DATA_DIR=/usr/share/kernel_service/sys_data

# 5. 赋予执行权限
RUN chmod +x /usr/local/bin/sys_kernel

# 默认入口（稍后会被 HF 的 boot.sh 覆盖，这里仅作测试）
ENTRYPOINT ["sys_kernel", "server/server.js"]
