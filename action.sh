#!/system/bin/sh

MODDIR="${0%/*}"
MANAGER="$MODDIR/scripts/manager.sh"

case "$1" in
    1)
        /system/bin/sh "$MANAGER" start
        ;;
    2)
        /system/bin/sh "$MANAGER" stop
        ;;
    3)
        /system/bin/sh "$MANAGER" restart
        ;;
    4)
        /system/bin/sh "$MANAGER" status
        ;;
    5)
        /system/bin/sh "$MANAGER" logs
        ;;
    6)
        /system/bin/sh "$MANAGER" version
        ;;
    *)
        echo "CF Server Monitor"
        echo "Usage:"
        echo "  1 start"
        echo "  2 stop"
        echo "  3 restart"
        echo "  4 status"
        echo "  5 logs"
        echo "  6 version"
        ;;
esac
