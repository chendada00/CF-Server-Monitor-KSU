#!/system/bin/sh

MODDIR="${0%/*}"

# 模块被禁用时不启动
[ -f "$MODDIR/disable" ] && exit 0

# 等 Android 系统和网络基本完成初始化
sleep 15

# 使用 sh 显式执行，不依赖脚本自身的执行权限
/system/bin/sh "$MODDIR/scripts/manager.sh" start \
    >> "/data/adb/cf-server-monitor/boot.log" 2>&1