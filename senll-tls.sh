#!/bin/bash

# 检查docker中是否存在senll相关的容器
if docker ps -a | grep -q 'senll'; then
  cd /root/snelldocker
  docker compose down
  echo -e "\e[32m清除旧环境成功！\e[0m"
  sleep 3
fi

# 更新系统包和升级
apt-get update && apt-get -y upgrade

# 安装 Docker
curl -fsSL https://get.docker.com | bash -s docker

# 判断并卸载不同版本的 Docker Compose
if [ -f "/usr/local/bin/docker-compose" ]; then
    sudo rm /usr/local/bin/docker-compose
fi

if [ -d "$HOME/.docker/cli-plugins/" ]; then
    rm -rf $HOME/.docker/cli-plugins/
fi

# 安装 Docker Compose 插件
apt-get install docker-compose-plugin -y

# 创建所需目录
mkdir -p /root/snelldocker/snell-conf

# 生成随机端口和密码
RANDOM_PORT=$(shuf -i 30000-65000 -n 1)
RANDOM_PSK=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20) # snell的随机密码
RANDOM_SHADOW_TLS_PSK=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 10) # shadow-tls的随机密码

# 创建 docker-compose.yml 和 snell.conf 配置文件
cat > /root/snelldocker/docker-compose.yml << EOF
version: "3.8"
services:
  snell:
    image: accors/snell:latest
    container_name: snell
    restart: always
    network_mode: host
    volumes:
      - ./snell-conf/snell.conf:/etc/snell-server.conf
    environment:
      - SNELL_URL=https://dl.nssurge.com/snell/snell-server-v4.0.1-linux-amd64.zip
  shadow-tls:
    image: ghcr.io/ihciah/shadow-tls:latest
    container_name: shadow-tls
    restart: always
    network_mode: "host"
    environment:
      - MODE=server
      - V3=1
      - LISTEN=0.0.0.0:8443
      - SERVER=127.0.0.1:$RANDOM_PORT
      - TLS=mp.weixin.qq.com:443
      - PASSWORD=$RANDOM_SHADOW_TLS_PSK
EOF

cat > /root/snelldocker/snell-conf/snell.conf << EOF
[snell-server]
listen = 0.0.0.0:$RANDOM_PORT
psk = $RANDOM_PSK
ipv6 = false
EOF

# 切换目录
cd /root/snelldocker

# 拉取并启动 Docker 容器
docker compose pull && docker compose up -d

# 获取本机IP地址
HOST_IP=$(curl -s http://checkip.amazonaws.com)

# 获取IP所在国家
IP_COUNTRY=$(curl -s http://ipinfo.io/$HOST_IP/country)

# 输出所需信息，包含IP所在国家
echo "$IP_COUNTRY = snell, $HOST_IP, 8443, psk = $RANDOM_PSK, version = 4, reuse = true, tfo = true, shadow-tls-password=$RANDOM_SHADOW_TLS_PSK, shadow-tls-sni=mp.weixin.qq.com, shadow-tls-version=3"
echo "请放行防火墙端口8443,$RANDOM_PORT"
