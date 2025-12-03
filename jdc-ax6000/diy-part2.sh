#!/bin/bash
#
# Copyright (c) 2019-2020 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#

# Modify default IP（按需启用：如果需要默认IP为192.168.123.1，取消下面注释）
# sed -i 's/192.168.1.1/192.168.123.1/g' package/base-files/files/bin/config_generate

##-----------------Del duplicate packages------------------
rm -rf feeds/packages/net/open-app-filter

##-----------------Add OpenClash dev core------------------
# curl -sL -m 30 --retry 2 https://raw.githubusercontent.com/vernesong/OpenClash/core/master/dev/clash-linux-arm64.tar.gz -o /tmp/clash.tar.gz
# tar zxvf /tmp/clash.tar.gz -C /tmp >/dev/null 2>&1
# chmod +x /tmp/clash >/dev/null 2>&1
# mkdir -p feeds/luci/applications/luci-app-openclash/root/etc/openclash/core
# mv /tmp/clash feeds/luci/applications/luci-app-openclash/root/etc/openclash/core/clash >/dev/null 2>&1
# rm -rf /tmp/clash.tar.gz >/dev/null 2>&1

##-----------------Delete DDNS's examples-----------------
# sed -i '/myddns_ipv4/,$d' feeds/packages/net/ddns-scripts/files/etc/config/ddns

# ==================== 整合ZRAM+CPU绑定+看门狗到rc.local ====================
COMPLETE_RC_LOCAL=$(cat << 'EOF'
#!/bin/sh

# ==================== ZRAM内存优化（512MB）====================
# 启用ZRAM压缩交换分区，释放物理内存，避免服务OOM崩溃
modprobe zram
echo lz4 > /sys/block/zram0/comp_algorithm  # 高效压缩算法（比gzip快）
echo 536870912 > /sys/block/zram0/disksize  # 分配512MB ZRAM空间
mkswap /dev/zram0                           # 格式化为swap分区
swapon /dev/zram0                           # 启用swap
echo "ZRAM已启用：512MB（lz4压缩），swap已激活"

# ==================== CPU核心绑定（进程隔离）====================
sleep 3  # 延迟3秒，等待核心进程启动

bind_process() {
    local pid=$(pidof $1)
    if [ -n "$pid" ]; then
        taskset -p $2 $pid > /dev/null 2>&1
        echo "已将进程 $1（PID: $pid）绑定到核心组 0x$2"
    fi
}

# 绑定网络基础进程到 CPU0+CPU1（0x3，低延迟优先）
bind_process "netifd" "3"
bind_process "hostapd" "3"
bind_process "dnsmasq" "3"
bind_process "uhttpd" "3"

# 绑定重负载进程到 CPU2+CPU3（0xc，高算力需求）
bind_process "nftables" "c"
bind_process "mtkwifi" "c"
bind_process "homeproxy" "c"
bind_process "AdGuardHome" "c"
bind_process "sing-box" "c"
bind_process "wireguard" "c"

# ==================== 中断亲和性优化 ====================
echo f > /proc/irq/default_smp_affinity
echo "默认中断亲和性已设置为 0xf（所有CPU核心）"

# ==================== 硬件看门狗（稳定兜底）====================
if [ -f /dev/watchdog ]; then
    watchdog -t 30 -v /dev/watchdog &  # 30秒喂狗，后台运行
    echo "硬件看门狗已启动（喂狗间隔30秒，PID: $!）"
else
    echo "警告：未找到硬件看门狗设备，跳过启用"
fi

exit 0
EOF
)

# 覆盖rc.local文件（确保固件内置）
RC_LOCAL="$GITHUB_WORKSPACE/openwrt/package/base-files/files/etc/rc.local"
echo "$COMPLETE_RC_LOCAL" > $RC_LOCAL
chmod +x $RC_LOCAL  # 赋予执行权限
echo "ZRAM+CPU绑定+看门狗已整合到 /etc/rc.local"

# ==================== 追加sysctl内核优化参数 ====================
SYSCTL_CONF="$GITHUB_WORKSPACE/openwrt/package/base-files/files/etc/sysctl.conf"
cat >> "$SYSCTL_CONF" << EOF
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.core.optmem_max = 65536
net.core.somaxconn = 131072
net.ipv4.tcp_mem = 102400 204800 409600
net.core.netdev_max_backlog = 131072
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_bbr_cca_params = max_bw_gain:10,min_rtt_gain:2
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_tw_reuse = 1 
net.ipv4.tcp_tw_recycle = 0  
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_sack = 1
net.ipv4.tcp_dsack = 1
net.ipv4.tcp_fack = 1
net.netfilter.nf_conntrack_max = 131072
net.netfilter.nf_conntrack_tcp_timeout_established = 86400
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
net.netfilter.nf_conntrack_udp_timeout = 30
net.netfilter.nf_conntrack_udp_timeout_stream = 120
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
vm.dirty_ratio = 30
vm.dirty_background_ratio = 10
fs.file-max = 1000000
fs.inotify.max_user_instances = 8192
vm.swappiness=10
vm.vfs_cache_pressure=50
net.ipv4.tcp_rmem=4096 131072 33554432
net.ipv4.tcp_wmem=4096 131072 33554432
EOF

echo "sysctl内核优化参数已追加到 /etc/sysctl.conf"
