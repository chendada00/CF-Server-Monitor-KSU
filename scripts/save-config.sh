#!/system/bin/sh

DATA_DIR="/data/adb/cf-server-monitor"

CONFIG="$DATA_DIR/config.conf"
TMP="$DATA_DIR/config.conf.tmp.$$"

KSU_BUSYBOX="/data/adb/ksu/bin/busybox"


mkdir -p "$DATA_DIR" || {
    echo "ERROR: failed to create data directory"
    exit 1
}


INPUT="$(cat)"


if [ -x "$KSU_BUSYBOX" ]; then

    DECODED="$(
        printf '%s' "$INPUT" |
        "$KSU_BUSYBOX" base64 -d 2>/dev/null
    )"

else

    DECODED="$(
        printf '%s' "$INPUT" |
        base64 -d 2>/dev/null
    )"

fi


if [ $? -ne 0 ]; then

    echo "ERROR: invalid base64 payload"

    exit 1

fi


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

    esac

done <<EOF
$DECODED
EOF


if [ -z "$SERVER_ID" ]; then

    echo "ERROR: SERVER_ID is required"

    exit 1

fi


if [ -z "$SECRET" ]; then

    echo "ERROR: SECRET is required"

    exit 1

fi


if [ -z "$WORKER_URL" ]; then

    echo "ERROR: WORKER_URL is required"

    exit 1

fi


case "$WORKER_URL" in

    http://*|https://*)
        ;;

    *)
        echo "ERROR: WORKER_URL must start with http:// or https://"
        exit 1
        ;;

esac


case "$COLLECT_INTERVAL" in

    ''|*[!0-9]*)
        echo "ERROR: COLLECT_INTERVAL must be a non-negative integer"
        exit 1
        ;;

esac


case "$REPORT_INTERVAL" in

    ''|*[!0-9]*)
        echo "ERROR: REPORT_INTERVAL must be a positive integer"
        exit 1
        ;;

esac


if [ "$REPORT_INTERVAL" -lt 1 ]; then

    echo "ERROR: REPORT_INTERVAL must be greater than 0"

    exit 1

fi


if [ "$COLLECT_INTERVAL" -gt 0 ] &&
   [ "$REPORT_INTERVAL" -lt "$COLLECT_INTERVAL" ]; then

    echo "ERROR: REPORT_INTERVAL cannot be less than COLLECT_INTERVAL"

    exit 1

fi


case "$RESET_DAY" in

    ''|*[!0-9]*)
        echo "ERROR: RESET_DAY must be 0-31"
        exit 1
        ;;

esac


if [ "$RESET_DAY" -gt 31 ]; then

    echo "ERROR: RESET_DAY must be 0-31"

    exit 1

fi


case "$CONNECTION_MODE" in

    auto|http)
        ;;

    *)
        echo "ERROR: CONNECTION_MODE must be auto or http"
        exit 1
        ;;

esac


case "$AUTO_UPDATE" in

    0|1)
        ;;

    *)
        echo "ERROR: AUTO_UPDATE must be 0 or 1"
        exit 1
        ;;

esac


escape_value() {

    printf '%s' "$1" |
        sed 's/[\\"]/\\&/g'

}


{

    echo "# CF Server Monitor Go Probe configuration"

    printf 'SERVER_ID="%s"\n' \
        "$(escape_value "$SERVER_ID")"

    printf 'SECRET="%s"\n' \
        "$(escape_value "$SECRET")"

    printf 'WORKER_URL="%s"\n' \
        "$(escape_value "$WORKER_URL")"


    printf 'COLLECT_INTERVAL="%s"\n' \
        "$COLLECT_INTERVAL"

    printf 'REPORT_INTERVAL="%s"\n' \
        "$REPORT_INTERVAL"


    printf 'CT_NODE="%s"\n' \
        "$(escape_value "$CT_NODE")"

    printf 'CU_NODE="%s"\n' \
        "$(escape_value "$CU_NODE")"

    printf 'CM_NODE="%s"\n' \
        "$(escape_value "$CM_NODE")"

    printf 'BD_NODE="%s"\n' \
        "$(escape_value "$BD_NODE")"


    printf 'INTERFACE="%s"\n' \
        "$(escape_value "$INTERFACE")"


    printf 'RESET_DAY="%s"\n' \
        "$RESET_DAY"


    printf 'CONNECTION_MODE="%s"\n' \
        "$CONNECTION_MODE"


    printf 'AUTO_UPDATE="%s"\n' \
        "$AUTO_UPDATE"

    printf 'UPDATE_PROXY="%s"\n' \
        "$(escape_value "$UPDATE_PROXY")"


    printf 'CONFIG_MD5="none"\n'

} > "$TMP"


if [ $? -ne 0 ]; then

    rm -f "$TMP"

    echo "ERROR: failed to write config"

    exit 1

fi


chmod 600 "$TMP" 2>/dev/null || true


mv -f "$TMP" "$CONFIG" || {

    rm -f "$TMP"

    echo "ERROR: failed to replace config"

    exit 1

}


echo "OK"