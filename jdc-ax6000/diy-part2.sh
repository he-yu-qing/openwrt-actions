#!/bin/bash
#
# OpenWrt DIY script part 2 (After Update feeds)
#

set -e

echo "===> DIY Part2 开始执行"

##----------------- 删除重复包 ------------------
rm -rf feeds/packages/net/open-app-filter 
rm -rf feeds/packages/net/adguardhome
# rm -rf feeds/packages/net/adguardhome  &&  rm -rf feeds/luci/applications/luci-app-adguardhome  &&  rm -rf feeds/packages/net/*adguardhome*  &&  rm -rf feeds/luci/applications/*luci-app-adguardhome*


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
# ==========================================
# MT7986（AX6000）精准优化版（基于真实IRQ）
# ==========================================

# ===== 1. 关闭 irqbalance =====
if [ -f /etc/init.d/irqbalance ]; then
    /etc/init.d/irqbalance stop
    /etc/init.d/irqbalance disable
fi

sleep 5

# ===== 2. IRQ 绑定函数 =====
bind_irq() {
    name="$1"
    mask="$2"
    for irq in $(grep "$name" /proc/interrupts | awk '{print $1}' | tr -d ':'); do
        echo "$mask" > /proc/irq/$irq/smp_affinity 2>/dev/null
        logger -t rc.local "IRQ绑定: $irq ($name) -> mask $mask"
    done
}

# ==========================================
# CPU 分工（按你当前最优状态）
# CPU0：系统 + 存储
# CPU1：有线网络
# CPU2：WO（WiFi加速）
# CPU3：WiFi
# ==========================================

# ===== 3. IRQ 精准绑定 =====

# WiFi（确认设备）
bind_irq "0000:00:00.0" 8

# 有线网络
bind_irq "15100000.ethernet" 2

# WiFi Offload（关键）
bind_irq "ccif_wo_isr" 4

# 存储
bind_irq "11230000.mmc" 1

# 加密
bind_irq "10320000.crypto" 1

# ===== 4. RPS/XPS（关闭）=====
echo 0 > /proc/sys/net/core/rps_sock_flow_entries

for net in /sys/class/net/eth*; do
    for f in "$net"/queues/rx-*/rps_cpus; do echo 0 > "$f"; done
    for f in "$net"/queues/tx-*/xps_cpus; do echo 0 > "$f"; done
done

# ===== 5. 进程绑核 =====
bind_process() {
    pname="$1"
    mask="$2"
    for pid in $(pidof "$pname" 2>/dev/null); do
        taskset -p "$mask" "$pid" >/dev/null 2>&1
    done
}

# 系统 → CPU0
bind_process "procd" 1
bind_process "logd" 1
bind_process "netifd" 1
bind_process "ubusd" 1

# 网络服务 → CPU1+2+3
bind_process "uhttpd" e
bind_process "dropbear" e

# DNS / 代理（关键）
bind_process "dnsmasq" e
bind_process "AdGuardHome" e
bind_process "homeproxy" e
bind_process "sing-box" e
bind_process "xray" e

# ===== 6. 系统优化 =====
echo 1000000 > /proc/sys/fs/file-max
echo 10 > /proc/sys/vm/swappiness

logger -t rc.local "MT7986 精准优化完成（按真实IRQ分布）"

exit 0
EOF

chmod +x "$RC_LOCAL"
echo "✔ rc.local 已写入"


# ==================== sysctl 优化 ====================
SYSCTL_CONF="package/base-files/files/etc/sysctl.conf"

cat >> "$SYSCTL_CONF" << 'EOF'
# ===== 队列 + BBR =====
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# ===== buffer（匹配1GB内存）=====
net.core.rmem_max=33554432
net.core.wmem_max=33554432
net.ipv4.tcp_rmem=4096 131072 33554432
net.ipv4.tcp_wmem=4096 131072 33554432

# ===== backlog（防止拥塞）=====
net.core.netdev_max_backlog=32768
net.core.somaxconn=65535

# ===== TCP 行为 =====
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_fin_timeout=30
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_max_syn_backlog=65535
net.ipv4.tcp_slow_start_after_idle=0

# ===== 内存控制 =====
net.ipv4.tcp_mem=262144 524288 1048576

# ===== conntrack =====
net.netfilter.nf_conntrack_max=131072

# ===== 安全 =====
net.ipv4.icmp_echo_ignore_broadcasts=1
net.ipv4.icmp_ignore_bogus_error_responses=1
net.ipv4.conf.all.accept_source_route=0
net.ipv4.conf.default.accept_source_route=0
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1

# ===== VM =====
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_ratio=15
vm.dirty_background_ratio=5
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
# fix_mtk_closed_source_opt


echo "===> DIY Part2 执行完成"
