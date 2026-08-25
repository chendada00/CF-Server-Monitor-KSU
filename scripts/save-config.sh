#!/system/bin/sh

DATA_DIR="/data/adb/cf-server-monitor"

CONFIG="$DATA_DIR/config.conf"
TMP="$CONFIG.tmp.$$"

mkdir -p "$DATA_DIR" || {
    echo "[错误] 无法创建数据目录：$DATA_DIR"
    exit 1
}

input=$(cat)

decoded=$(
    printf '%s' "$input" |
        base64 -d 2>/dev/null
) || {
    echo "[错误] 无法解析配置数据"
    exit 1
}

SERVER_ID=""
SECRET=""
WORKER_URL=""

COLLECT_INTERVAL=""
REPORT_INTERVAL=""

CT_NODE=""
CU_NODE=""
CM_NODE=""
BD_NODE=""

INTERFACE=""

RESET_DAY=""

CONNECTION_MODE=""

AUTO_UPDATE=""
UPDATE_PROXY=""

DEBUG=""
LOG_MAX_SIZE_MB=""
LOG_KEEP_COUNT=""


while IFS='=' read -r key value; do

    case "$key" in

        SERVER_ID)
            SERVER_ID="$value"
            ;;

        SECRET)
            SECRET="$value"
            ;;

        WORKER_URL)
            WORKER_URL="$value"
            ;;

        COLLECT_INTERVAL)
            COLLECT_INTERVAL="$value"
            ;;

        REPORT_INTERVAL)
            REPORT_INTERVAL="$value"
            ;;

        CT_NODE)
            CT_NODE="$value"
            ;;

        CU_NODE)
            CU_NODE="$value"
            ;;

        CM_NODE)
            CM_NODE="$value"
            ;;

        BD_NODE)
            BD_NODE="$value"
            ;;

        INTERFACE)
            INTERFACE="$value"
            ;;

        RESET_DAY)
            RESET_DAY="$value"
            ;;

        CONNECTION_MODE)
            CONNECTION_MODE="$value"
            ;;

        AUTO_UPDATE)
            AUTO_UPDATE="$value"
            ;;

        UPDATE_PROXY)
            UPDATE_PROXY="$value"
            ;;

        DEBUG)
            DEBUG="$value"
            ;;

        LOG_MAX_SIZE_MB)
            LOG_MAX_SIZE_MB="$value"
            ;;

        LOG_KEEP_COUNT)
            LOG_KEEP_COUNT="$value"
            ;;

    esac

done <<EOF
$decoded
EOF


[ -n "$SERVER_ID" ] || {
    echo "[错误] Server ID 不能为空"
    exit 1
}

[ -n "$SECRET" ] || {
    echo "[错误] Secret 不能为空"
    exit 1
}

[ -n "$WORKER_URL" ] || {
    echo "[错误] Worker URL 不能为空"
    exit 1
}


case "$COLLECT_INTERVAL" in

    ''|*[!0-9]*)
        echo "[错误] 采集间隔必须是数字"
        exit 1
        ;;

esac


case "$REPORT_INTERVAL" in

    ''|*[!0-9]*)
        echo "[错误] 上报间隔必须是数字"
        exit 1
        ;;

esac


case "$RESET_DAY" in

    ''|*[!0-9]*)
        RESET_DAY="1"
        ;;

esac


case "$CONNECTION_MODE" in

    auto|http)
        ;;

    *)
        echo "[错误] CONNECTION_MODE 只能是 auto 或 http"
        exit 1
        ;;

esac


case "$AUTO_UPDATE" in

    0|1)
        ;;

    *)
        AUTO_UPDATE="0"
        ;;

esac


case "$DEBUG" in

    0|1)
        ;;

    *)
        DEBUG="0"
        ;;

esac


case "$LOG_MAX_SIZE_MB" in

    ''|*[!0-9]*)
        LOG_MAX_SIZE_MB="5"
        ;;

esac

[ "$LOG_MAX_SIZE_MB" -gt 0 ] 2>/dev/null ||
    LOG_MAX_SIZE_MB="5"


case "$LOG_KEEP_COUNT" in

    ''|*[!0-9]*)
        LOG_KEEP_COUNT="3"
        ;;

esac

[ "$LOG_KEEP_COUNT" -gt 0 ] 2>/dev/null ||
    LOG_KEEP_COUNT="3"


escape_dq() {

    printf '%s' "$1" |
        sed 's/[\\$`"]/\\&/g'
}


{
    echo "# CF Server Monitor Android / KernelSU 配置"

    printf 'SERVER_ID="%s"\n' \
        "$(escape_dq "$SERVER_ID")"

    printf 'SECRET="%s"\n' \
        "$(escape_dq "$SECRET")"

    printf 'WORKER_URL="%s"\n' \
        "$(escape_dq "$WORKER_URL")"

    printf 'COLLECT_INTERVAL="%s"\n' \
        "$COLLECT_INTERVAL"

    printf 'REPORT_INTERVAL="%s"\n' \
        "$REPORT_INTERVAL"

    printf 'CT_NODE="%s"\n' \
        "$(escape_dq "$CT_NODE")"

    printf 'CU_NODE="%s"\n' \
        "$(escape_dq "$CU_NODE")"

    printf 'CM_NODE="%s"\n' \
        "$(escape_dq "$CM_NODE")"

    printf 'BD_NODE="%s"\n' \
        "$(escape_dq "$BD_NODE")"

    printf 'INTERFACE="%s"\n' \
        "$(escape_dq "$INTERFACE")"

    printf 'RESET_DAY="%s"\n' \
        "$RESET_DAY"

    printf 'CONNECTION_MODE="%s"\n' \
        "$CONNECTION_MODE"

    printf 'AUTO_UPDATE="%s"\n' \
        "$AUTO_UPDATE"

    printf 'UPDATE_PROXY="%s"\n' \
        "$(escape_dq "$UPDATE_PROXY")"

    printf 'CONFIG_MD5="%s"\n' \
        "none"

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