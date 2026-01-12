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
	option fullcone6 '1'
	option synflood_protect '1'
	option drop_invalid '1'

config zone
	option name 'lan'
	list network 'lan'
	option input 'ACCEPT'
	option output 'ACCEPT'
	option forward 'ACCEPT'

config zone
	option name 'wan'
	list network 'wan'
	list network 'wan6'
	option input 'DROP'
	option output 'ACCEPT'
	option forward 'DROP'
	option masq '1'
	option mtu_fix '1'

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
	option input 'REJECT'
	option output 'ACCEPT'
	option forward 'REJECT'
	option log '0'

config rule
	option name 'wireguard'
	option src 'wan'
	option target 'ACCEPT'
	list proto 'udp'
	option family 'ipv6'
	option dest_port '64189'

config forwarding
	option src 'wireguard'
	option dest 'lan'

config forwarding
	option src 'wireguard'
	option dest 'wan'

config include 'homeproxy_forward'
	option type 'nftables'
	option path '/var/run/homeproxy/fw4_forward.nft'
	option position 'chain-pre'
	option chain 'forward'

config include 'homeproxy_input'
	option type 'nftables'
	option path '/var/run/homeproxy/fw4_input.nft'
	option position 'chain-pre'
	option chain 'input'

config include 'homeproxy_post'
	option type 'nftables'
	option path '/var/run/homeproxy/fw4_post.nft'
	option position 'table-post'

config include 'passwall'
	option type 'script'
	option path '/var/etc/passwall.include'
	option reload '1'

config include 'passwall_server'
	option type 'script'
	option path '/var/etc/passwall_server.include'
	option reload '1'

config redirect 'adguardhome_dns_udp'
	option name 'AdGuardHome DNS UDP'
	option src 'lan'
	option proto 'udp'
	option src_dport '53'
	option dest_port '5553'
	option target 'DNAT'
	option family 'any'

config redirect 'adguardhome_dns_tcp'
	option name 'AdGuardHome DNS TCP'
	option src 'lan'
	option proto 'tcp'
	option src_dport '53'
	option dest_port '5553'
	option target 'DNAT'
	option family 'any'

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

config redirect 'adguardhome_redirect'
	option target 'DNAT'
	option name 'AdGuard Home'
	option src 'lan'
	option family 'any'
	option src_dport '53'
	option dest_port '5553'

EOF
)

# 覆盖默认防火墙配置
DEFAULT_FIREWALL_PATH="$GITHUB_WORKSPACE/openwrt/package/network/config/firewall/files/firewall.config"
echo "$CUSTOM_FIREWALL" > "$DEFAULT_FIREWALL_PATH"
chmod 644 "$DEFAULT_FIREWALL_PATH"
echo "自定义防火墙规则已成功覆盖默认配置！路径：$DEFAULT_FIREWALL_PATH"
