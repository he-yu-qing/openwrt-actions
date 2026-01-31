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
sleep 5
bind_irq() {
    name="$1"
    mask="$2"
       for irq in $(grep "$name" /proc/interrupts | awk '{print $1}' | tr -d ':'); do
        if [ -d "/proc/irq/$irq" ]; then
            echo "$mask" > /proc/irq/$irq/smp_affinity
            logger -t "rc.local" "优化绑定: IRQ $irq ($name) -> CPU掩码 $mask"
        fi
    done
}
bind_irq "0000:00:00.0" 8
bind_irq "ccif_wo_isr" 8
bind_irq "15100000.ethernet" 6
bind_irq "11230000.mmc" 1
bind_irq "10320000.crypto" 1
for net in /sys/class/net/eth*; do
    [ -d "$net" ] || continue
    for rps in "$net"/queues/rx-*/rps_cpus; do echo f > "$rps"; done
    for xps in "$net"/queues/tx-*/xps_cpus; do echo f > "$xps"; done
done

bind_process() {
    pname="$1"
    mask="$2"
    for pid in $(pidof "$pname"); do
        taskset -p "$mask" "$pid" >/dev/null 2>&1
    done
}
bind_process "netifd" 1
bind_process "ubus" 1
bind_process "dnsmasq" 1
bind_process "logd" 1
bind_process "procd" 1
bind_process "uhttpd" 6
bind_process "dropbear" 6
bind_process "sing-box" 4
bind_process "xray" 4
bind_process "AdGuardHome" 4
bind_process "homeproxy" 4
bind_process "mosdns" 4
logger -t "rc.local" "极致性能优化脚本执行完毕：Wi-Fi(CPU3), Eth(CPU1/2), App(分流)"
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
