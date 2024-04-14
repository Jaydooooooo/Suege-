#!/bin/bash

echo "开始卸载操作..."

# 停止snell服务
sudo systemctl stop snell
echo "snell服务已停止。"

# 禁用snell服务
sudo systemctl disable snell
echo "snell服务已禁用。"

# 移除systemd服务文件
sudo rm /etc/systemd/system/snell.service
echo "snell服务文件已删除。"

# 删除snell服务器文件
rm -f $HOME/snell-server
echo "snell服务器文件已删除。"

# 删除配置文件（如果存在）
rm -f $HOME/snell-server.conf
echo "snell配置文件已删除。"

# 恢复sysctl配置
sudo sed -i '/net.core.default_qdisc=fq/d' /etc/sysctl.conf
sudo sed -i '/net.ipv4.tcp_congestion_control=bbr/d' /etc/sysctl.conf
sudo sysctl -p
echo "BBR配置已恢复。"

# 检查并卸载wget, unzip, dpkg (如果不再需要，可以注释掉这一部分)
# 根据Linux发行版卸载依赖
if cat /etc/*-release | grep -q -E -i "debian|ubuntu|armbian|deepin|mint"; then
    sudo apt-get remove wget unzip dpkg -y
elif cat /etc/*-release | grep -q -E -i "centos|red hat|redhat"; then
    sudo yum remove wget unzip dpkg -y
elif cat /etc/*-release | grep -q -E -i "arch|manjaro"; then
    sudo pacman -R wget dpkg unzip
elif cat /etc/*-release | grep -q -E -i "fedora"; then
    sudo dnf remove wget unzip dpkg -y
fi
echo "依赖已卸载。"

echo "卸载完成。"
