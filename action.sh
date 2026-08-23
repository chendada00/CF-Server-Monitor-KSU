#!/system/bin/sh
MODDIR=${0%/*}
MANAGER="$MODDIR/scripts/manager.sh"

echo "=============================="
echo "   CF Server Monitor"
echo "=============================="
echo
"$MANAGER" status
echo
echo "1) Start"
echo "2) Stop"
echo "3) Restart"
echo "4) Show status"
echo "5) Show last 100 log lines"
echo
printf "Select [1-5]: "
read -r choice

case "$choice" in
    1) "$MANAGER" start ;;
    2) "$MANAGER" stop ;;
    3) "$MANAGER" restart ;;
    4) "$MANAGER" status ;;
    5) "$MANAGER" logs ;;
    *) echo "Invalid selection" ;;
esac
