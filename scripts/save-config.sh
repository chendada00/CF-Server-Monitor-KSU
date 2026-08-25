#!/system/bin/sh

MODDIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

CONFIG="$MODDIR/config/config.conf"
TMP="$CONFIG.tmp.$$"

input=$(cat)

decoded=$(
    printf '%s' "$input" |
    base64 -d 2>/dev/null
) || {
    echo "[错误] 无法解析配置数据"
    exit 1
}

ID=""
SECRET=""
URL=""
INTERVAL=""
COLLECT_INTERVAL=""
CONNECTION_MODE=""
DEBUG=""
LOG_MAX_SIZE_MB=""
LOG_KEEP_COUNT=""

while IFS='=' read -r key value; do

    case "$key" in

        ID)
            ID=$value
            ;;

        SECRET)
            SECRET=$value
            ;;

        URL)
            URL=$value
            ;;

        INTERVAL)
            INTERVAL=$value
            ;;

        COLLECT_INTERVAL)
            COLLECT_INTERVAL=$value
            ;;

        CONNECTION_MODE)
            CONNECTION_MODE=$value
            ;;

        DEBUG)
            DEBUG=$value
            ;;

        LOG_MAX_SIZE_MB)
            LOG_MAX_SIZE_MB=$value
            ;;

        LOG_KEEP_COUNT)
            LOG_KEEP_COUNT=$value
            ;;
    esac

done <<EOF
$decoded
EOF

[ -n "$ID" ] || {
    echo "[错误] Agent ID 不能为空"
    exit 1
}

[ -n "$SECRET" ] || {
    echo "[错误] Secret 不能为空"
    exit 1
}

[ -n "$URL" ] || {
    echo "[错误] 服务端地址不能为空"
    exit 1
}

case "$INTERVAL" in

    ''|*[!0-9]*)
        echo "[错误] 上报间隔必须是数字"
        exit 1
        ;;
esac

case "$COLLECT_INTERVAL" in

    ''|*[!0-9]*)
        echo "[错误] 采集间隔必须是数字"
        exit 1
        ;;
esac

case "$CONNECTION_MODE" in

    http|https)
        ;;
    *)
        echo "[错误] 连接方式只能是 http 或 https"
        exit 1
        ;;
esac

case "$DEBUG" in

    0|1)
        ;;
    *)
        DEBUG=0
        ;;
esac

case "$LOG_MAX_SIZE_MB" in

    ''|*[!0-9]*)
        LOG_MAX_SIZE_MB=5
        ;;
esac

[ "$LOG_MAX_SIZE_MB" -gt 0 ] ||
    LOG_MAX_SIZE_MB=5

case "$LOG_KEEP_COUNT" in

    ''|*[!0-9]*)
        LOG_KEEP_COUNT=3
        ;;
esac

[ "$LOG_KEEP_COUNT" -gt 0 ] ||
    LOG_KEEP_COUNT=3

escape_dq() {

    printf '%s' "$1" |
        sed 's/[\\$`"]/\\&/g'
}

{
    echo "# CF Server Monitor Android / KernelSU 配置"

    printf 'ID="%s"\n' \
        "$(escape_dq "$ID")"

    printf 'SECRET="%s"\n' \
        "$(escape_dq "$SECRET")"

    printf 'URL="%s"\n' \
        "$(escape_dq "$URL")"

    printf 'INTERVAL="%s"\n' \
        "$INTERVAL"

    printf 'COLLECT_INTERVAL="%s"\n' \
        "$COLLECT_INTERVAL"

    printf 'CONNECTION_MODE="%s"\n' \
        "$CONNECTION_MODE"

    printf 'DEBUG="%s"\n' \
        "$DEBUG"

    printf 'LOG_MAX_SIZE_MB="%s"\n' \
        "$LOG_MAX_SIZE_MB"

    printf 'LOG_KEEP_COUNT="%s"\n' \
        "$LOG_KEEP_COUNT"

} > "$TMP" || {
    rm -f "$TMP"
    echo "[错误] 无法写入临时配置"
    exit 1
}

mv "$TMP" "$CONFIG" || {
    rm -f "$TMP"
    echo "[错误] 保存配置失败"
    exit 1
}

chmod 600 "$CONFIG" 2>/dev/null || true

echo "OK"
echo "配置保存成功。"