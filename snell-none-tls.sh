#!/bin/bash

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

# 创建systemd服务
echo -e "[Unit]\nDescription=snell server\n[Service]\nUser=$(whoami)\nWorkingDirectory=$HOME\nExecStart=$HOME/snell-server\nRestart=always\n[Install]\nWantedBy=multi-user.target" | sudo tee /etc/systemd/system/snell.service > /dev/null
echo "y" | sudo ./snell-server
sudo systemctl start snell
sudo systemctl enable snell

# 将snell-server.conf中的ipv6设置修改为true
sudo sed -i 's/ipv6 = false/ipv6 = true/' snell-server.conf

# 打印配置信息，包括ipv6设置
echo
echo "复制以下行到surge"
ipv6_setting=$(grep 'ipv6' snell-server.conf | cut -d= -f2 | tr -d ' ')
echo "$(curl -s ipinfo.io/city) = snell, $(curl -s ipinfo.io/ip), $(cat snell-server.conf | grep -i listen | cut --delimiter=':' -f2), psk=$(grep 'psk' snell-server.conf | cut -d= -f2 | tr -d ' '), ipv6=${ipv6_setting}, version=4, tfo=true"
