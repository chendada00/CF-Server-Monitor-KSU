#!/system/bin/sh

MODDIR="${0%/*}"
MANAGER="$MODDIR/scripts/manager.sh"

echo "================================"
echo "   CF Server Monitor"
echo "================================"
echo

echo "1. Start"
echo "2. Stop"
echo "3. Restart"
echo "4. Status"
echo "5. Logs"
echo "6. Version"

echo
printf "Select [1-6]: "

read -r CHOICE

case "$CHOICE" in
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
        echo "Invalid selection"
        ;;
esac