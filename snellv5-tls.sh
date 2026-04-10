#!/bin/bash

set -euo pipefail

echo "=========================================="
echo "   Docker 安装 Snell v5 + ShadowTLS v3"
echo "=========================================="

if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 root 用户运行此脚本。"
    exit 1
fi

ARCH=$(uname -m)
case "$ARCH" in
    x86_64) SNELL_ARCH="amd64" ;;
    aarch64|arm64) SNELL_ARCH="aarch64" ;;
    armv7l) SNELL_ARCH="armv7l" ;;
    i386|i686) SNELL_ARCH="i386" ;;
    *)
        echo "不支持的架构: $ARCH"
        exit 1
        ;;
esac

SNELL_VERSION="v5.0.1"
SNELL_URL="https://dl.nssurge.com/snell/snell-server-${SNELL_VERSION}-linux-${SNELL_ARCH}.zip"
WORKDIR="/opt/snell-v5-shadowtls"
SNELL_PORT=$(shuf -i 10000-60000 -n 1)
SHADOW_TLS_PORT=8443

gen_secret() {
    local length="$1"
    local secret
    if command -v openssl >/dev/null 2>&1; then
        secret=$(openssl rand -hex 32)
    else
        secret=$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')
    fi
    printf '%s' "${secret:0:length}"
}

SNELL_PSK=$(gen_secret 24)
SHADOW_TLS_PSK=$(gen_secret 16)

echo "检测到架构: $ARCH"
echo "Snell 下载地址: $SNELL_URL"

if ! command -v docker >/dev/null 2>&1; then
    echo "Docker 未安装，开始安装..."
    apt-get update -qq
    curl -fsSL https://get.docker.com | bash
    systemctl enable docker
    systemctl start docker
fi

if ! docker compose version >/dev/null 2>&1; then
    echo "docker compose 插件未安装，开始安装..."
    apt-get update -qq
    apt-get install -y docker-compose-plugin
fi

for container in snell snell-v5 shadow-tls shadow-tls-v3; do
    if docker ps -a --format '{{.Names}}' | grep -qx "$container"; then
        echo "清理旧容器: $container"
        docker stop "$container" >/dev/null 2>&1 || true
        docker rm "$container" >/dev/null 2>&1 || true
    fi
done

mkdir -p "$WORKDIR"

cat > "$WORKDIR/snell-server.conf" << CONF
[snell-server]
listen = 127.0.0.1:${SNELL_PORT}
psk = ${SNELL_PSK}
ipv6 = false
CONF

cat > "$WORKDIR/Dockerfile" << DOCKERFILE
FROM debian:bookworm-slim

ARG SNELL_URL
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends wget unzip ca-certificates && \
    rm -rf /var/lib/apt/lists/*

RUN wget -q "\${SNELL_URL}" -O /tmp/snell.zip && \
    unzip -q /tmp/snell.zip -d /usr/local/bin/ && \
    chmod +x /usr/local/bin/snell-server && \
    rm -f /tmp/snell.zip

RUN mkdir -p /etc/snell

CMD ["/usr/local/bin/snell-server", "-c", "/etc/snell/snell-server.conf"]
DOCKERFILE

cat > "$WORKDIR/docker-compose.yml" << EOF
services:
  snell-v5:
    build:
      context: .
      dockerfile: Dockerfile
      args:
        SNELL_URL: ${SNELL_URL}
    container_name: snell-v5
    restart: always
    network_mode: host
    volumes:
      - ./snell-server.conf:/etc/snell/snell-server.conf:ro

  shadow-tls-v3:
    image: ghcr.io/ihciah/shadow-tls:latest
    container_name: shadow-tls-v3
    restart: always
    network_mode: host
    environment:
      MODE: server
      V3: "1"
      LISTEN: 0.0.0.0:${SHADOW_TLS_PORT}
      SERVER: 127.0.0.1:${SNELL_PORT}
      TLS: mp.weixin.qq.com:443
      PASSWORD: ${SHADOW_TLS_PSK}
EOF

echo "启动 Snell v5 + ShadowTLS v3..."
cd "$WORKDIR"
docker compose down --remove-orphans >/dev/null 2>&1 || true
docker compose up -d --build

SERVER_IP=$(curl -s4 --max-time 5 ifconfig.me 2>/dev/null || true)
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(curl -s4 --max-time 5 ip.sb 2>/dev/null || true)
fi
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(curl -s4 --max-time 5 api.ipify.org 2>/dev/null || true)
fi
if [ -z "$SERVER_IP" ]; then
    SERVER_IP="YOUR_SERVER_IP"
fi

INFO_FILE="$WORKDIR/surge-config.txt"
cat > "$INFO_FILE" << INFO
========================================
Snell v5 + ShadowTLS v3 安装信息
========================================
服务器 IP : ${SERVER_IP}
ShadowTLS 端口 : ${SHADOW_TLS_PORT}
Snell PSK      : ${SNELL_PSK}
ShadowTLS 密码 : ${SHADOW_TLS_PSK}
版本           : 5

Surge 配置行（v5）：
Snell-V5-TLS = snell, ${SERVER_IP}, ${SHADOW_TLS_PORT}, psk=${SNELL_PSK}, version=5, reuse=true, tfo=true, shadow-tls-password=${SHADOW_TLS_PSK}, shadow-tls-sni=mp.weixin.qq.com, shadow-tls-version=3

Surge 配置行（v4 兼容）：
Snell-V5-TLS = snell, ${SERVER_IP}, ${SHADOW_TLS_PORT}, psk=${SNELL_PSK}, version=4, reuse=true, tfo=true, shadow-tls-password=${SHADOW_TLS_PSK}, shadow-tls-sni=mp.weixin.qq.com, shadow-tls-version=3
========================================
INFO

echo ""
echo "=========================================="
echo "Snell v5 + ShadowTLS v3 安装完成"
echo "=========================================="
echo "服务器 IP        : ${SERVER_IP}"
echo "ShadowTLS 端口   : ${SHADOW_TLS_PORT}"
echo "Snell PSK        : ${SNELL_PSK}"
echo "ShadowTLS 密码   : ${SHADOW_TLS_PSK}"
echo ""
echo "Surge 配置（v5，推荐）:"
echo "Snell-V5-TLS = snell, ${SERVER_IP}, ${SHADOW_TLS_PORT}, psk=${SNELL_PSK}, version=5, reuse=true, tfo=true, shadow-tls-password=${SHADOW_TLS_PSK}, shadow-tls-sni=mp.weixin.qq.com, shadow-tls-version=3"
echo ""
echo "Surge 配置（v4 兼容）:"
echo "Snell-V5-TLS = snell, ${SERVER_IP}, ${SHADOW_TLS_PORT}, psk=${SNELL_PSK}, version=4, reuse=true, tfo=true, shadow-tls-password=${SHADOW_TLS_PSK}, shadow-tls-sni=mp.weixin.qq.com, shadow-tls-version=3"
echo ""
echo "配置已保存到: $INFO_FILE"
echo "请放行防火墙端口: ${SHADOW_TLS_PORT}"
