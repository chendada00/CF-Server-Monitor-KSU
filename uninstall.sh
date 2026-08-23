#!/system/bin/sh

MODDIR="${0%/*}"

/system/bin/sh "$MODDIR/scripts/manager.sh" stop >/dev/null 2>&1 || true

# 删除运行时 PID
rm -f /data/adb/cf-server-monitor/cf-probe.pid

# 注意：
# 这里暂时不删除 config.conf。
#
# 这样可以避免用户重新安装模块时丢失配置。
#
# 如果你希望“卸载模块就彻底删除配置和日志”，
# 可以改成：
#
# rm -rf /data/adb/cf-server-monitor