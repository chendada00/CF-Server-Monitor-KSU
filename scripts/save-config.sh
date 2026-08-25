#!/system/bin/sh

DATA_DIR="/data/adb/cf-server-monitor"
CONFIG="$DATA_DIR/config.conf"
TMP="$CONFIG.tmp.$$"

mkdir -p "$DATA_DIR" || {
    echo "[错误] 无法创建数据目录：$DATA_DIR"
    exit 1
}

INPUT=$(cat)

DECODED=$(
    printf '%s' "$INPUT" |
        base64 -d 2>/dev/null
) || {
    echo "[错误] 无法解析配置数据"
    exit 1
}

SERVER_ID=""
SECRET=""
WORKER_URL=""

COLLECT_INTERVAL="0"
REPORT_INTERVAL="60"

CT_NODE=""
CU_NODE=""
CM_NODE=""
BD_NODE=""

INTERFACE=""
RESET_DAY="1"

CONNECTION_MODE="auto"

AUTO_UPDATE="0"
UPDATE_PROXY=""

DEBUG="0"
LOG_MAX_SIZE_MB="5"
LOG_KEEP_COUNT="3"


while IFS='=' read -r KEY VALUE; do

    case "$KEY" in

        SERVER_ID)
            SERVER_ID="$VALUE"
            ;;

        SECRET)
            SECRET="$VALUE"
            ;;

        WORKER_URL)
            WORKER_URL="$VALUE"
            ;;

        COLLECT_INTERVAL)
            COLLECT_INTERVAL="$VALUE"
            ;;

        REPORT_INTERVAL)
            REPORT_INTERVAL="$VALUE"
            ;;

        CT_NODE)
            CT_NODE="$VALUE"
            ;;

        CU_NODE)
            CU_NODE="$VALUE"
            ;;

        CM_NODE)
            CM_NODE="$VALUE"
            ;;

        BD_NODE)
            BD_NODE="$VALUE"
            ;;

        INTERFACE)
            INTERFACE="$VALUE"
            ;;

        RESET_DAY)
            RESET_DAY="$VALUE"
            ;;

        CONNECTION_MODE)
            CONNECTION_MODE="$VALUE"
            ;;

        AUTO_UPDATE)
            AUTO_UPDATE="$VALUE"
            ;;

        UPDATE_PROXY)
            UPDATE_PROXY="$VALUE"
            ;;

        DEBUG)
            DEBUG="$VALUE"
            ;;

        LOG_MAX_SIZE_MB)
            LOG_MAX_SIZE_MB="$VALUE"
            ;;

        LOG_KEEP_COUNT)
            LOG_KEEP_COUNT="$VALUE"
            ;;

    esac

done <<EOF
$DECODED
EOF


# 去除可能存在的双引号
SERVER_ID=${SERVER_ID#\"}
SERVER_ID=${SERVER_ID%\"}

SECRET=${SECRET#\"}
SECRET=${SECRET%\"}

WORKER_URL=${WORKER_URL#\"}
WORKER_URL=${WORKER_URL%\"}

COLLECT_INTERVAL=${COLLECT_INTERVAL#\"}
COLLECT_INTERVAL=${COLLECT_INTERVAL%\"}

REPORT_INTERVAL=${REPORT_INTERVAL#\"}
REPORT_INTERVAL=${REPORT_INTERVAL%\"}

CT_NODE=${CT_NODE#\"}
CT_NODE=${CT_NODE%\"}

CU_NODE=${CU_NODE#\"}
CU_NODE=${CU_NODE%\"}

CM_NODE=${CM_NODE#\"}
CM_NODE=${CM_NODE%\"}

BD_NODE=${BD_NODE#\"}
BD_NODE=${BD_NODE%\"}

INTERFACE=${INTERFACE#\"}
INTERFACE=${INTERFACE%\"}

RESET_DAY=${RESET_DAY#\"}
RESET_DAY=${RESET_DAY%\"}

CONNECTION_MODE=${CONNECTION_MODE#\"}
CONNECTION_MODE=${CONNECTION_MODE%\"}

AUTO_UPDATE=${AUTO_UPDATE#\"}
AUTO_UPDATE=${AUTO_UPDATE%\"}

UPDATE_PROXY=${UPDATE_PROXY#\"}
UPDATE_PROXY=${UPDATE_PROXY%\"}

DEBUG=${DEBUG#\"}
DEBUG=${DEBUG%\"}

LOG_MAX_SIZE_MB=${LOG_MAX_SIZE_MB#\"}
LOG_MAX_SIZE_MB=${LOG_MAX_SIZE_MB%\"}

LOG_KEEP_COUNT=${LOG_KEEP_COUNT#\"}
LOG_KEEP_COUNT=${LOG_KEEP_COUNT%\"}


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

    echo "[错误] 无法写入配置文件"

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