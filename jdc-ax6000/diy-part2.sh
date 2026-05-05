#!/bin/bash
#
# OpenWrt DIY script part 2 (After Update feeds)
#

set -e

echo "===> DIY Part2 开始执行"

##----------------- 删除重复包 ------------------
rm -rf feeds/packages/net/open-app-filter  &&  rm -rf feeds/packages/net/open-app-filter  &&  rm -rf feeds/packages/net/adguardhome  &&  rm -rf feeds/luci/applications/luci-app-adguardhome  &&  rm -rf feeds/packages/net/*adguardhome*  &&  rm -rf feeds/luci/applications/*luci-app-adguardhome*


# ==================== MTK 闭源驱动优化隔离 ====================
fix_mtk_closed_source_opt() {
    MTK_DIR="package/mtk/drivers"

    echo "===> [MTK FIX] 禁用闭源驱动高阶优化"

    if [ ! -d "$MTK_DIR" ]; then
        echo "❌ [MTK FIX] 目录不存在: $MTK_DIR"
        return 1
    fi

    local count=0

    while read -r mk; do

        if ! grep -q "kernel.mk" "$mk"; then
            continue
        fi

        if grep -q "MTK_CLOSED_SRC_OPT_FIX" "$mk"; then
            continue
        fi

        echo "✔ patch: $mk"

        cat >> "$mk" << 'EOF'

# ===== MTK_CLOSED_SRC_OPT_FIX START =====
EXTRA_CFLAGS += -O2 \
                -fno-lto \
                -fno-ipa-sra \
                -fno-ipa-cp \
                -fno-tree-vectorize \
                -fno-graphite-identity \
                -fno-loop-nest-optimize

KBUILD_CFLAGS += -fno-lto
KCFLAGS += -fno-lto
KBUILD_LDFLAGS += -fuse-ld=bfd
# ===== MTK_CLOSED_SRC_OPT_FIX END =====

EOF

        count=$((count+1))

    done < <(find "$MTK_DIR" -name Makefile)

    echo "===> [MTK FIX] 完成（处理 Makefile 数量: $count）"
}


# ==================== rc.local 性能优化 ====================
RC_LOCAL="package/base-files/files/etc/rc.local"
mkdir -p "$(dirname "$RC_LOCAL")"

cat > "$RC_LOCAL" << 'EOF'
#!/bin/sh

# ==============================
# MT7986 极致性能优化 rc.local
# ==============================

/etc/init.d/irqbalance stop 2>/dev/null
/etc/init.d/irqbalance disable 2>/dev/null

sleep 10

bind_irq() {
    name="$1"
    mask="$2"
    for irq in $(grep "$name" /proc/interrupts | awk '{print $1}' | tr -d ':'); do
        [ -d "/proc/irq/$irq" ] && echo "$mask" > /proc/irq/$irq/smp_affinity
    done
}

# CPU3：WiFi
bind_irq "mt76" 8

# CPU2：WED/HNAT
bind_irq "ccif" 4

# CPU1+2：以太网
bind_irq "ethernet" 6

# CPU0：存储/加密
bind_irq "mmc" 1
bind_irq "crypto" 1

echo 32768 > /proc/sys/net/core/rps_sock_flow_entries

for net in /sys/class/net/eth*; do
    [ -d "$net" ] || continue

    for rps in "$net"/queues/rx-*/rps_cpus; do echo 6 > "$rps"; done
    for xps in "$net"/queues/tx-*/xps_cpus; do echo 6 > "$xps"; done
    for flow in "$net"/queues/rx-*/rps_flow_cnt; do echo 4096 > "$flow"; done
done

bind_process() {
    pname="$1"
    mask="$2"
    for pid in $(pidof "$pname"); do
        taskset -p "$mask" "$pid" >/dev/null 2>&1
    done
}

# CPU0：系统
bind_process "procd" 1
bind_process "logd" 1
bind_process "netifd" 1
bind_process "ubus" 1
bind_process "dnsmasq" 1

# CPU1+2：服务
bind_process "uhttpd" 6
bind_process "dropbear" 6
bind_process "AdGuardHome" 6
bind_process "homeproxy" 6
bind_process "mosdns" 6
bind_process "sing-box" 6
bind_process "xray" 6

logger -t rc.local "MT7986 优化已生效"

exit 0
EOF

chmod +x "$RC_LOCAL"
echo "✔ rc.local 已写入"


# ==================== sysctl 优化 ====================
SYSCTL_CONF="package/base-files/files/etc/sysctl.conf"

cat >> "$SYSCTL_CONF" << 'EOF'
net.core.rmem_max=33554432
net.core.wmem_max=33554432
net.core.somaxconn=131072
net.core.netdev_max_backlog=131072

net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_fin_timeout=30
net.ipv4.tcp_max_syn_backlog=65535

net.netfilter.nf_conntrack_max=131072

vm.swappiness=10
vm.vfs_cache_pressure=50
EOF

echo "✔ sysctl 优化已写入"


# ==================== 防火墙优化 ====================
FIREWALL="package/network/config/firewall/files/firewall.config"

cat > "$FIREWALL" << 'EOF'
config defaults
	option input 'REJECT'
	option output 'ACCEPT'
	option forward 'REJECT'
	option synflood_protect '1'
	option flow_offloading '1'
	option flow_offloading_hw '1'

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
	list network 'wan'
	list network 'wan6'

config forwarding
	option src 'lan'
	option dest 'wan'

config redirect
	option name 'AdGuardHome DNS'
	option src 'lan'
	option proto 'tcp udp'
	option src_dport '53'
	option dest_port '5553'
	option target 'DNAT'
EOF

echo "✔ 防火墙规则已写入"


# ==================== 执行 MTK 修复 ====================
fix_mtk_closed_source_opt


echo "===> DIY Part2 执行完成"
