#!/bin/bash
#
# OpenWrt DIY script part 2 (After Update feeds)
#

set -e

echo "===> DIY Part2 开始执行"

##----------------- 删除重复包 ------------------
rm -rf feeds/packages/net/open-app-filter  && rm -rf feeds/packages/net/adguardhome && rm -rf feeds/luci/applications/luci-app-adguardhome && rm -rf feeds/packages/net/*adguardhome*  &&  rm -rf feeds/luci/applications/*luci-app-adgua
# rm -rf feeds/packages/net/adguardhome  &&  rm -rf feeds/luci/applications/luci-app-adguardhome  &&  rm -rf feeds/packages/net/*adguardhome*  &&  rm -rf feeds/luci/applications/*luci-app-adguardhome*


echo "===> DIY Part2 执行完成"
