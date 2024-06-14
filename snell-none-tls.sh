#!/bin/bash

# 获取用户输入的端口和PSK密码，如果没有输入则随机生成
read -p "请输入要使用的端口号（默认随机生成）: " PORT
read -p "请输入要使用的PSK密码（默认随机生成）: " PSK

# 如果端口号为空，则随机生成一个1024-65535之间的端口号
if [ -z "$PORT" ]; then
    PORT=$((RANDOM % 64512 + 1024))
fi

# 如果PSK密码为空，则随机生成一个32位的密码
if [ -z "$PSK" ]; then
    PSK=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32)
fi

apt update && sudo apt install -y wget unzip

# 根据Linux发行版安装依赖
if cat /etc/*-release | grep -q -E -i "debian|ubuntu|armbian|deepin|mint"; then
    sudo apt-get install wget unzip dpkg -y
elif cat /etc/*-release | grep -q -E -i "centos|red hat|redhat"; then
    sudo yum install wget unzip dpkg -y
elif cat /etc/*-release | grep -q -E -i "arch|manjaro"; then
    sudo pacman -S wget dpkg unzip --noconfirm
elif cat /etc/*-release | grep -q -E -i "fedora"; then
    sudo dnf install wget unzip dpkg -y
fi

# 启用BBR
echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
sudo sysctl net.ipv4.tcp_available_congestion_control

cd
ARCH=$(uname -m)
BASE_URL="https://dl.nssurge.com/snell/snell-server-v4.0.1-linux"
case $ARCH in
    "x86_64")
        PACKAGE="${BASE_URL}-amd64.zip"
        ;;
    "i686" | "i386")
        PACKAGE="${BASE_URL}-i386.zip"
        ;;
    "aarch64")
        PACKAGE="${BASE_URL}-aarch64.zip"
        ;;
    "armv7l")
        PACKAGE="${BASE_URL}-armv7l.zip"
        ;;
    *)
        echo "不支持的架构: $ARCH"
        exit 1
        ;;
esac
wget $PACKAGE

if [ $? -ne 0 ]; then
    echo "下载失败！"
    exit 1
fi
unzip -o ${PACKAGE##*/}

# 创建snell配置文件
cat > snell-server.conf <<EOF
[snell-server]
listen = 0.0.0.0:$PORT
psk = $PSK
ipv6 = false
EOF

# 创建systemd服务
echo -e "[Unit]\nDescription=snell server\n[Service]\nUser=$(whoami)\nWorkingDirectory=$HOME\nExecStart=$HOME/snell-server\nRestart=always\n[Install]\nWantedBy=multi-user.target" | sudo tee /etc/systemd/system/snell.service > /dev/null

# 启动并启用Snell服务
sudo systemctl start snell
sudo systemctl enable snell

# 验证Snell服务是否启动
sudo systemctl status snell | grep 'Active: active (running)' > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "Snell 服务器成功启动！"
else
    echo "Snell 服务器启动失败！"
    exit 1
fi

# 将snell-server.conf中的ipv6设置修改为true
sudo sed -i 's/ipv6 = false/ipv6 = true/' snell-server.conf

# 打印配置信息，包括ipv6设置
echo
echo "复制以下行到surge"
ipv6_setting=$(grep 'ipv6' snell-server.conf | cut -d= -f2 | tr -d ' ')
echo "$(curl -s ipinfo.io/city) = snell, $(curl -s ipinfo.io/ip), $PORT, psk=$PSK, ipv6=${ipv6_setting}, version=4, tfo=true"
