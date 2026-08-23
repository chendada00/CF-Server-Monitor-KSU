#!/system/bin/sh
MODDIR=${0%/*}

# Do not start while the module is disabled.
[ -f "$MODDIR/disable" ] && exit 0

# Give Android networking and services a little time to settle.
sleep 10

"$MODDIR/scripts/manager.sh" start >> "$MODDIR/logs/boot.log" 2>&1
