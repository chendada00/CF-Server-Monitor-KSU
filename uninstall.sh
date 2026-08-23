#!/system/bin/sh
MODDIR=${0%/*}
"$MODDIR/scripts/manager.sh" stop >/dev/null 2>&1 || true
