#!/system/bin/sh

MODDIR=${0%/*}

MANAGER="$MODDIR/scripts/manager.sh"

sleep 15

if [ -x "$MANAGER" ]; then

    "$MANAGER" start \
        >/data/adb/cf-server-monitor/boot.log \
        2>&1

fi