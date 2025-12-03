#!/bin/bash
# （保留原有版权注释...）

##-----------------Del duplicate packages------------------
# 关键修正：将该命令移出 RC_LOCAL，作为顶层命令（编译时执行）
rm -rf feeds/packages/net/open-app-filter

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

# （后续的 RC_LOCAL 覆盖、sysctl.conf 追加代码不变...）
