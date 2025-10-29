#!/bin/bash
# 适配 GitHub 云编译 + padavanonly/immortalwrt-mt798x-6.6 源码
# 复刻本地编译成功逻辑：解决 warp_wifi.h 头文件缺失问题

# 定义核心路径（无需修改，与云编译环境对齐）
OPENWRT_ROOT="/workdir/openwrt"
SRC_WARP_DIR="${OPENWRT_ROOT}/package/mtk/drivers/warp/src"
INCLUDE_DIR="${OPENWRT_ROOT}/staging_dir/target-aarch64_cortex-a53_musl/usr/include"
MT_WIFI_BUILD_DIR="${OPENWRT_ROOT}/build_dir/target-aarch64_cortex-a53_musl/linux-mediatek_filogic/mt_wifi"

# 1. 复制 warp 头文件到编译器搜索目录
echo -e "\n[1/4] 复制 warp 头文件..."
mkdir -p "${INCLUDE_DIR}" || { echo "❌ 创建 include 目录失败"; exit 1; }
cp -r "${SRC_WARP_DIR}"/* "${INCLUDE_DIR}/" || { echo "❌ 复制头文件失败"; exit 1; }
echo "✅ 头文件复制完成"

# 2. 验证关键文件存在性
echo -e "\n[2/4] 验证核心文件..."
REQUIRED_FILES=(
    "${INCLUDE_DIR}/mcu/warp_wo.h"
    "${INCLUDE_DIR}/warp.h"
    "${INCLUDE_DIR}/warp_wifi.h"
)
for file in "${REQUIRED_FILES[@]}"; do
    [ -f "${file}" ] && echo "✅ 找到：${file}" || { echo "❌ 缺失：${file}"; exit 1; }
done

# 3. 修复文件权限
echo -e "\n[3/4] 修复权限..."
chmod -R 644 "${INCLUDE_DIR}"/* || { echo "❌ 修复文件权限失败"; exit 1; }
chmod -R 755 "${INCLUDE_DIR}/mcu" || { echo "❌ 修复 mcu 目录权限失败"; exit 1; }
echo "✅ 权限修复完成"

# 4. 清理 mt_wifi 编译残留
echo -e "\n[4/4] 清理编译缓存..."
[ -d "${MT_WIFI_BUILD_DIR}" ] && rm -rf "${MT_WIFI_BUILD_DIR}" && echo "✅ 删除动态生成目录" || echo "ℹ️ 无需删除动态目录"
cd "${OPENWRT_ROOT}" || { echo "❌ 进入源码目录失败"; exit 1; }
make package/mtk/drivers/mt_wifi/clean > /dev/null 2>&1 || { echo "❌ 清理编译标记失败"; exit 1; }
echo "✅ 缓存清理完成"

echo -e "\n🎉 所有前置操作执行完毕，开始编译 mt_wifi 驱动"
exit 0
