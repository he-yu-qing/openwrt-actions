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

##-----------------Del duplicate packages------------------
rm -rf feeds/packages/net/open-app-filter
rm -rf feeds/packages/net/sing-box



COMPLETE_RC_LOCAL=$(cat << 'EOF'
#!/bin/sh

# 1. 禁用 irqbalance 以防覆盖手动设置 (极致性能必须独占控制权)
/etc/init.d/irqbalance stop 2>/dev/null
/etc/init.d/irqbalance disable 2>/dev/null

sleep 5 # 等待驱动完全加载

# 辅助函数：将中断绑定到特定 CPU (Hex掩码)
# 参数 1: 关键词 (如 eth0, mt7986)
# 参数 2: CPU掩码 (Hex: 1=CPU0, 2=CPU1, 4=CPU2, 8=CPU3)
bind_irq() {
    for irq in $(grep "$1" /proc/interrupts | cut -d: -f1 | tr -d ' '); do
        if [ -d "/proc/irq/$irq" ]; then
            echo "$2" > /proc/irq/$irq/smp_affinity
            echo "IRQ $irq ($1) -> CPU Mask $2" > /dev/console
        fi
    done
}

# --- 中断绑定 (针对 MT7986 4核 A53 优化) ---
# CPU0 (1): 系统基础中断/软中断
# CPU1 (2): LAN 中断
# CPU2 (4): WAN 中断
# CPU3 (8): Wi-Fi 中断 (吞吐量大户)

# 动态查找并绑定 Wi-Fi (mt7986-wmac) 到 CPU3
bind_irq "mt7986-wmac" 8

# 动态查找并绑定 Ethernet (eth0/eth1)
# 注意：OpenWrt 中 eth0/eth1 的物理对应关系可能随版本变化，建议基于驱动名
# 通常 11280000.ethernet 是以太网控制器
bind_irq "ethernet" 6  # 将以太网中断分散到 CPU1 和 CPU2 (Mask 6 = 4+2)

# --- RPS/XPS 软队列优化 (网卡多队列) ---
# 启用所有 CPU 处理软中断接收，防止单核打满
for net in /sys/class/net/eth*; do
    [ -d "$net" ] || continue
    # RPS: 接收包转向 (Receive Packet Steering) -> 均衡到所有核心 (f)
    for rps in "$net"/queues/rx-*/rps_cpus; do echo f > "$rps"; done
    # XPS: 发送包转向 (Transmit Packet Steering) -> 均衡到所有核心 (f)
    for xps in "$net"/queues/tx-*/xps_cpus; do echo f > "$xps"; done
done

# --- 进程绑定 (Taskset) ---
# 辅助函数：绑定进程名下的所有 PID
bind_process() {
    pname="$1"
    mask="$2" # 这里的 mask 是十六进制
    for pid in $(pidof "$pname"); do
        taskset -p "$mask" "$pid" >/dev/null 2>&1
    done
}

# 网络核心进程 -> CPU 0,1 (Mask 3)
bind_process "netifd" 3
bind_process "ubus" 3
bind_process "uhttpd" 3
bind_process "dnsmasq" 3

# 高负载插件 -> CPU 2,3 (Mask c)
# 让出 CPU 0/1 给内核和网络中断
bind_process "xray" c
bind_process "sing-box" c
bind_process "AdGuardHome" c
bind_process "homeproxy" c
bind_process "mosdns" c

exit 0
EOF
)

# 写入文件并赋予权限
RC_LOCAL="$GITHUB_WORKSPACE/openwrt/package/base-files/files/etc/rc.local"
# 确保目录存在
mkdir -p "$(dirname "$RC_LOCAL")"
echo "$COMPLETE_RC_LOCAL" > "$RC_LOCAL"
chmod +x "$RC_LOCAL"
echo "/etc/rc.local"



# ==================== 追加sysctl内核优化参数（核心执行步骤，之前缺失）====================
SYSCTL_CONF="$GITHUB_WORKSPACE/openwrt/package/base-files/files/etc/sysctl.conf"
cat >> "$SYSCTL_CONF" << EOF
# User defined entries should be added to this file not to /etc/sysctl.d/* as
# that directory is not backed-up by default and will not survive a reimag
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
net.ipv4.tcp_max_tw_buckets = 200000
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
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
fs.file-max = 1000000
fs.inotify.max_user_instances = 8192
vm.swappiness=10
vm.vfs_cache_pressure=50
net.ipv4.tcp_rmem=4096 131072 33554432
net.ipv4.tcp_wmem=4096 131072 33554432

EOF
echo "sysctl内核优化参数已追加到 /etc/sysctl.conf"

# ==================== 内置自定义防火墙规则 ====================
CUSTOM_FIREWALL=$(cat << 'EOF'

config defaults
	option input 'REJECT'
	option output 'ACCEPT'
	option forward 'REJECT'
	option synflood_protect '1'
	option drop_invalid '1'
	option flow_offloading_hw '0'
	option flow_offloading '0'
	option fullcone '0'

config zone
	option name 'lan'
	option input 'ACCEPT'
	option output 'ACCEPT'
	option forward 'ACCEPT'
	list network 'lan'

config zone
	option name 'wan'
	option input 'DROP'
	option output 'ACCEPT'
	option forward 'DROP'
	option masq '1'
	option mtu_fix '1'
	list network 'wan'
	list network 'wan6'
	list network 'moden'

config forwarding
	option src 'lan'
	option dest 'wan'

config rule
	option name 'Allow-DHCP-Renew'
	option src 'wan'
	option proto 'udp'
	option dest_port '68'
	option target 'ACCEPT'
	option family 'ipv4'

config rule
	option name 'Allow-Ping'
	option src 'wan'
	option proto 'icmp'
	option icmp_type 'echo-request'
	option family 'ipv4'
	option target 'ACCEPT'
	option enabled '0'

config rule
	option name 'Allow-IGMP'
	option src 'wan'
	option proto 'igmp'
	option family 'ipv4'
	option target 'ACCEPT'

config rule
	option name 'Allow-DHCPv6'
	option src 'wan'
	option proto 'udp'
	option dest_port '546'
	option family 'ipv6'
	option target 'ACCEPT'

config rule
	option name 'Allow-MLD'
	option src 'wan'
	option proto 'icmp'
	option src_ip 'fe80::/10'
	list icmp_type '130/0'
	list icmp_type '131/0'
	list icmp_type '132/0'
	list icmp_type '143/0'
	option family 'ipv6'
	option target 'ACCEPT'

config rule
	option name 'Allow-ICMPv6-Input'
	option src 'wan'
	option proto 'icmp'
	list icmp_type 'echo-request'
	list icmp_type 'echo-reply'
	list icmp_type 'destination-unreachable'
	list icmp_type 'packet-too-big'
	list icmp_type 'time-exceeded'
	list icmp_type 'bad-header'
	list icmp_type 'unknown-header-type'
	list icmp_type 'router-solicitation'
	list icmp_type 'neighbour-solicitation'
	list icmp_type 'router-advertisement'
	list icmp_type 'neighbour-advertisement'
	option limit '1000/sec'
	option family 'ipv6'
	option target 'ACCEPT'

config rule
	option name 'Allow-ICMPv6-Forward'
	option src 'wan'
	option dest '*'
	option proto 'icmp'
	list icmp_type 'echo-request'
	list icmp_type 'echo-reply'
	list icmp_type 'destination-unreachable'
	list icmp_type 'packet-too-big'
	list icmp_type 'time-exceeded'
	list icmp_type 'bad-header'
	list icmp_type 'unknown-header-type'
	option limit '1000/sec'
	option family 'ipv6'
	option target 'ACCEPT'

config rule
	option name 'Allow-IPSec-ESP'
	option src 'wan'
	option dest 'lan'
	option proto 'esp'
	option target 'ACCEPT'

config rule
	option name 'Allow-ISAKMP'
	option src 'wan'
	option dest 'lan'
	option dest_port '500'
	option proto 'udp'
	option target 'ACCEPT'

config zone
	option name 'IPTV'
	option input 'ACCEPT'
	option output 'ACCEPT'
	option forward 'ACCEPT'
	list network 'IPTV'

config rule
	option name 'IPTV-Allow-IGMP'
	option src 'IPTV'
	option proto 'igmp'
	option target 'ACCEPT'
	option family 'ipv4'

config zone
	option name 'wireguard'
	option input 'ACCEPT'
	option output 'ACCEPT'
	option forward 'ACCEPT'
	list network 'wireguard'

config rule
	option name 'wireguard'
	option src 'wan'
	option target 'ACCEPT'
	option family 'ipv6'
	option dest_port '64189'
	list proto 'tcp'
	list proto 'udp'

config forwarding
	option src 'wireguard'
	option dest 'lan'

config forwarding
	option src 'wireguard'
	option dest 'wan'

config rule
	option name 'Block-External-DNS'
	option src 'lan'
	option dest 'wan'
	option proto 'tcp udp'
	option dest_port '53'
	option target 'REJECT'

config rule
	option name 'Block-External-DNS-IPv6'
	option src 'lan'
	option dest 'wan'
	option proto 'tcp udp'
	option dest_port '53'
	option family 'ipv6'
	option target 'REJECT'

config redirect
	option name 'AdGuardHome DNS'
	option src 'lan'
	option proto 'tcp udp'
	option src_dport '53'
	option dest_port '5553'
	option target 'DNAT'
	option family 'any'

EOF
)

# 覆盖默认防火墙配置
DEFAULT_FIREWALL_PATH="$GITHUB_WORKSPACE/openwrt/package/network/config/firewall/files/firewall.config"
echo "$CUSTOM_FIREWALL" > "$DEFAULT_FIREWALL_PATH"
chmod 644 "$DEFAULT_FIREWALL_PATH"
echo "自定义防火墙规则已成功覆盖默认配置！路径：$DEFAULT_FIREWALL_PATH"
