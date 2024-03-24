#!/bin/bash

# Cloudflare API 凭据
AUTH_EMAIL="your_mail@mail.com"  # Cloudflare 账户邮箱
AUTH_KEY="your_global_api_key"          # 你的 Cloudflare Global API Key
CF_ZONE_ID="your_zone_id_here"          # 你的 Cloudflare Zone ID
RECORD_NAME="cera.gooutside.xyz"        # 你希望更新的 DNS 记录名称
PRIMARY_IP="x,x,x,x"             # 主 IP 地址
BACKUP_IP="x,x,x,x"             # 备用 IP 地址
PORT="01010"                            # 你希望检查的端口

# 检查IP端口是否开放
check_port() {
    timeout 5 bash -c "cat < /dev/null > /dev/tcp/${1}/${PORT}" 2> /dev/null
    return $?
}

# 更新Cloudflare DNS记录
update_dns() {
    local ip=$1
    # 获取DNS记录ID
    local record_id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?type=A&name=${RECORD_NAME}" \
        -H "X-Auth-Email: ${AUTH_EMAIL}" \
        -H "X-Auth-Key: ${AUTH_KEY}" \
        -H "Content-Type: application/json" | jq -r ".result[0].id")
    
    # 检查是否成功获取DNS记录ID
    if [[ $record_id == "null" ]]; then
        echo "Failed to retrieve DNS record ID."
        return
    fi

    # 更新DNS记录
    local update_response=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${record_id}" \
        -H "X-Auth-Email: ${AUTH_EMAIL}" \
        -H "X-Auth-Key: ${AUTH_KEY}" \
        -H "Content-Type: application/json" \
        --data '{"type":"A","name":"'"${RECORD_NAME}"'","content":"'"${ip}"'"}')

    # 输出结果
    echo "DNS record updated to IP: $ip."
}

# 主循环
while true; do
    if check_port $PRIMARY_IP; then
        # 如果主 IP 可用且当前 DNS 不是主 IP，则更新为主 IP
        update_dns $PRIMARY_IP
    else
        # 如果主 IP 不可用，则切换到备用 IP
        update_dns $BACKUP_IP
    fi
    sleep 10
done
