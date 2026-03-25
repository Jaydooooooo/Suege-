#!/bin/bash

set -e

echo "=========================================="
echo "      Docker 安装 Snell v5 脚本"
echo "=========================================="

# ─── 检测架构 ───────────────────────────────
ARCH=$(uname -m)
case $ARCH in
    x86_64)  SNELL_ARCH="amd64"   ;;
    aarch64) SNELL_ARCH="aarch64" ;;
    armv7l)  SNELL_ARCH="armv7l"  ;;
    i386|i686) SNELL_ARCH="i386"  ;;
    *)
        echo "❌ 不支持的架构: $ARCH"
        exit 1
        ;;
esac

SNELL_VERSION="v5.0.1"
SNELL_URL="https://dl.nssurge.com/snell/snell-server-${SNELL_VERSION}-linux-${SNELL_ARCH}.zip"

echo "📦 检测到架构: $ARCH  →  使用包: snell-server-${SNELL_VERSION}-linux-${SNELL_ARCH}.zip"

# ─── 检查 / 安装 Docker ────────────────────
if ! command -v docker &>/dev/null; then
    echo "🐳 Docker 未安装，正在自动安装..."
    apt-get update -qq
    curl -fsSL https://get.docker.com | bash
    systemctl enable docker
    systemctl start docker
    echo "✅ Docker 安装完成"
else
    echo "✅ Docker 已安装: $(docker --version)"
fi

# ─── 停止 / 清理旧容器 ────────────────────
if docker ps -a --format '{{.Names}}' | grep -q '^snell-v5$'; then
    echo "🔄 发现旧的 snell-v5 容器，正在清理..."
    docker stop snell-v5 2>/dev/null || true
    docker rm   snell-v5 2>/dev/null || true
fi

# ─── 生成随机 PSK 和端口 ──────────────────
PSK=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 24)
PORT=$(shuf -i 10000-60000 -n 1)

# 如果 openssl 不可用，备用方案
if [ -z "$PSK" ]; then
    PSK=$(cat /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 24)
fi

echo "🔑 生成 PSK : $PSK"
echo "🔌 使用端口 : $PORT"

# ─── 创建工作目录 ────────────────────────
WORKDIR="/opt/snell-v5"
mkdir -p "$WORKDIR"

# ─── 写入 Snell 配置文件 ─────────────────
cat > "$WORKDIR/snell-server.conf" << CONF
[snell-server]
listen = 0.0.0.0:${PORT}
psk = ${PSK}
ipv6 = false
CONF

echo "📝 配置文件已写入 $WORKDIR/snell-server.conf"

# ─── 构建 Docker 镜像 ────────────────────
cat > "$WORKDIR/Dockerfile" << DOCKERFILE
FROM debian:bookworm-slim

ARG SNELL_URL
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends wget unzip ca-certificates && \
    rm -rf /var/lib/apt/lists/*

RUN wget -q "${SNELL_URL}" -O /tmp/snell.zip && \
    unzip -q /tmp/snell.zip -d /usr/local/bin/ && \
    chmod +x /usr/local/bin/snell-server && \
    rm /tmp/snell.zip

RUN mkdir -p /etc/snell

EXPOSE ${PORT}/tcp
EXPOSE ${PORT}/udp

CMD ["/usr/local/bin/snell-server", "-c", "/etc/snell/snell-server.conf"]
DOCKERFILE

echo "🔨 正在构建 Docker 镜像（snell-v5）..."
docker build \
    --build-arg SNELL_URL="$SNELL_URL" \
    -t snell-v5-image \
    "$WORKDIR"

# ─── 启动容器 ────────────────────────────
echo "🚀 正在启动容器..."
docker run -d \
    --name snell-v5 \
    --restart always \
    -p "${PORT}:${PORT}/tcp" \
    -p "${PORT}:${PORT}/udp" \
    -v "$WORKDIR/snell-server.conf:/etc/snell/snell-server.conf:ro" \
    snell-v5-image

# ─── 获取服务器公网 IP ──────────────────
echo "🌐 正在获取服务器公网 IP..."
SERVER_IP=$(curl -s4 --max-time 5 ifconfig.me 2>/dev/null)
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(curl -s4 --max-time 5 ip.sb 2>/dev/null)
fi
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(curl -s4 --max-time 5 api.ipify.org 2>/dev/null)
fi
if [ -z "$SERVER_IP" ]; then
    SERVER_IP="YOUR_SERVER_IP"
    echo "⚠️  无法自动获取公网IP，请手动替换配置中的 YOUR_SERVER_IP"
fi

# ─── 保存配置信息 ────────────────────────
INFO_FILE="$WORKDIR/surge-config.txt"
cat > "$INFO_FILE" << INFO
========================================
Snell v5 安装信息
========================================
服务器 IP : ${SERVER_IP}
端口       : ${PORT}
PSK        : ${PSK}
版本       : 5

Surge 配置行（v5 协议）：
Snell-V5 = snell, ${SERVER_IP}, ${PORT}, psk=${PSK}, version=5, reuse=true, tfo=true

Surge 配置行（v4 兼容，不含 QUIC Proxy）：
Snell-V5 = snell, ${SERVER_IP}, ${PORT}, psk=${PSK}, version=4, reuse=true, tfo=true
========================================
INFO

# ─── 打印结果 ────────────────────────────
echo ""
echo "=========================================="
echo "✅  Snell v5 安装完成！"
echo "=========================================="
echo ""
echo "  服务器 IP : ${SERVER_IP}"
echo "  端口       : ${PORT}"
echo "  PSK        : ${PSK}"
echo ""
echo "📋 Surge 配置（复制以下任意一行到 Surge）："
echo ""
echo "  # v5 版本（支持 QUIC Proxy，推荐）"
echo "  Snell-V5 = snell, ${SERVER_IP}, ${PORT}, psk=${PSK}, version=5, reuse=true, tfo=true"
echo ""
echo "  # v4 兼容版本"
echo "  Snell-V5 = snell, ${SERVER_IP}, ${PORT}, psk=${PSK}, version=4, reuse=true, tfo=true"
echo ""
echo "📁 配置信息已保存至: $INFO_FILE"
echo ""
echo "🔧 常用命令："
echo "  查看状态 : docker ps | grep snell-v5"
echo "  查看日志 : docker logs snell-v5"
echo "  停止服务 : docker stop snell-v5"
echo "  卸载     : docker stop snell-v5 && docker rm snell-v5"
echo "=========================================="
