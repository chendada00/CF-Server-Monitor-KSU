#!/system/bin/sh

MODDIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

BIN="$MODDIR/bin/cf-probe"

DATADIR="/data/adb/cf-server-monitor"

CONFIG="$DATADIR/config.conf"

DEFAULT_CONFIG="$MODDIR/config/config.conf"

PIDFILE="$DATADIR/cf-probe.pid"

LOGDIR="$DATADIR/logs"
LOGFILE="$LOGDIR/cf-probe.log"

ACTION_LOG="$DATADIR/webui-action.log"

KSU_BUSYBOX="/data/adb/ksu/bin/busybox"

CF_PROBE_UPDATE_DNS_SERVER="223.5.5.5"

DEFAULT_LOG_MAX_SIZE_MB=5
DEFAULT_LOG_KEEP_COUNT=3


mkdir -p "$DATADIR" "$LOGDIR"


log() {
    printf '%s\n' "$*"
}


now() {
    date '+%Y-%m-%d %H:%M:%S'
}


write_manager_log() {

    printf '%s %s\n' \
        "[$(now)]" \
        "$*" \
        >> "$LOGFILE"
}


init_config() {

    if [ -f "$CONFIG" ]; then
        return 0
    fi


    if [ ! -f "$DEFAULT_CONFIG" ]; then

        log "[错误] 找不到默认配置文件：$DEFAULT_CONFIG"

        return 1
    fi


    cp "$DEFAULT_CONFIG" "$CONFIG" || {

        log "[错误] 无法创建运行时配置：$CONFIG"

        return 1
    }


    chmod 600 "$CONFIG" 2>/dev/null || true
}


load_config() {

    init_config || return 1


    if [ ! -r "$CONFIG" ]; then

        log "[错误] 配置文件不可读：$CONFIG"

        return 1
    fi


    # shellcheck disable=SC1090
    . "$CONFIG"


    SERVER_ID="${SERVER_ID:-}"
    SECRET="${SECRET:-}"
    WORKER_URL="${WORKER_URL:-}"

    COLLECT_INTERVAL="${COLLECT_INTERVAL:-0}"
    REPORT_INTERVAL="${REPORT_INTERVAL:-60}"

    CT_NODE="${CT_NODE:-}"
    CU_NODE="${CU_NODE:-}"
    CM_NODE="${CM_NODE:-}"
    BD_NODE="${BD_NODE:-}"

    INTERFACE="${INTERFACE:-}"

    RESET_DAY="${RESET_DAY:-1}"

    CONNECTION_MODE="${CONNECTION_MODE:-auto}"

    AUTO_UPDATE="${AUTO_UPDATE:-0}"
    UPDATE_PROXY="${UPDATE_PROXY:-}"

    DEBUG="${DEBUG:-0}"

    LOG_MAX_SIZE_MB="${LOG_MAX_SIZE_MB:-$DEFAULT_LOG_MAX_SIZE_MB}"
    LOG_KEEP_COUNT="${LOG_KEEP_COUNT:-$DEFAULT_LOG_KEEP_COUNT}"


    [ -n "$SERVER_ID" ] || {

        log "[错误] Server ID 不能为空"

        return 1
    }


    [ -n "$SECRET" ] || {

        log "[错误] Secret 不能为空"

        return 1
    }


    [ -n "$WORKER_URL" ] || {

        log "[错误] Worker URL 不能为空"

        return 1
    }
}


get_ssl_cert_dir() {

    if [ -d "/apex/com.android.conscrypt/cacerts" ]; then

        printf '%s' \
            "/apex/com.android.conscrypt/cacerts"

        return
    fi


    if [ -d "/system/etc/security/cacerts" ]; then

        printf '%s' \
            "/system/etc/security/cacerts"

        return
    fi


    printf '%s' ""
}


pid_alive() {

    pid="$1"


    [ -n "$pid" ] ||
        return 1


    case "$pid" in

        ''|*[!0-9]*)
            return 1
            ;;

    esac


    [ "$pid" -gt 0 ] ||
        return 1


    [ -r "/proc/$pid/cmdline" ] ||
        return 1


    cmdline=$(
        tr '\000' ' ' \
            < "/proc/$pid/cmdline" \
            2>/dev/null
    )


    case "$cmdline" in

        *"$BIN"*)
            return 0
            ;;

        *)
            return 1
            ;;

    esac
}


find_probe_pid() {

    if [ -x "$KSU_BUSYBOX" ]; then

        "$KSU_BUSYBOX" pgrep -f \
            "$BIN" \
            2>/dev/null |
            head -n 1

        return
    fi


    pidof cf-probe 2>/dev/null |
        awk '{print $1}'
}


get_pid() {

    if [ -f "$PIDFILE" ]; then

        pid=$(cat "$PIDFILE" 2>/dev/null)


        case "$pid" in

            ''|*[!0-9]*)
                pid=""
                ;;

        esac


        if [ -n "$pid" ] &&
            pid_alive "$pid"; then

            printf '%s\n' "$pid"

            return 0
        fi
    fi


    pid=$(find_probe_pid)


    if [ -n "$pid" ] &&
        pid_alive "$pid"; then

        printf '%s\n' "$pid"

        return 0
    fi


    rm -f "$PIDFILE"

    return 1
}


is_running() {

    get_pid >/dev/null 2>&1
}


get_file_size() {

    file="$1"


    [ -f "$file" ] || {

        printf '0'

        return
    }


    wc -c < "$file" 2>/dev/null |
        tr -d ' '
}


rotate_logs() {

    load_config >/dev/null 2>&1 ||
        return 0


    [ -f "$LOGFILE" ] ||
        return 0


    max_bytes=$(
        echo "$LOG_MAX_SIZE_MB * 1024 * 1024" |
            awk '{print $1 * $3}'
    )


    [ "$max_bytes" -gt 0 ] 2>/dev/null ||
        return 0


    current_size=$(get_file_size "$LOGFILE")


    [ "$current_size" -lt "$max_bytes" ] &&
        return 0


    i="$LOG_KEEP_COUNT"


    while [ "$i" -gt 1 ]; do

        prev=$((i - 1))


        if [ -f "$LOGFILE.$prev" ]; then

            mv \
                "$LOGFILE.$prev" \
                "$LOGFILE.$i" \
                2>/dev/null || true
        fi


        i="$prev"

    done


    if [ -f "$LOGFILE" ]; then

        mv \
            "$LOGFILE" \
            "$LOGFILE.1" \
            2>/dev/null || true
    fi


    : > "$LOGFILE"
}


clear_logs() {

    : > "$LOGFILE"

    rm -f "$LOGFILE".[0-9]*

    log "日志已清空。"

    update_module_description
}


update_module_description() {

    if pid=$(get_pid); then

        desc="● 探针运行中 | PID=$pid"

    else

        desc="● 探针已停止"
    fi


    if [ -f "$CONFIG" ]; then

        # shellcheck disable=SC1090
        . "$CONFIG" 2>/dev/null || true


        desc="$desc | 上报=${REPORT_INTERVAL:-60}秒"


        if [ "${DEBUG:-0}" = "1" ]; then

            desc="$desc | 调试已开启"
        fi
    fi


    if command -v ksud >/dev/null 2>&1; then

        ksud module config set \
            override.description \
            "$desc" \
            >/dev/null 2>&1 || true

    elif [ -x "/data/adb/ksud" ]; then

        /data/adb/ksud module config set \
            override.description \
            "$desc" \
            >/dev/null 2>&1 || true
    fi
}


validate_config() {

    load_config ||
        return 1


    case "$REPORT_INTERVAL" in

        ''|*[!0-9]*)

            log "[错误] 上报间隔必须是数字"

            return 1
            ;;

    esac


    case "$COLLECT_INTERVAL" in

        ''|*[!0-9]*)

            log "[错误] 采集间隔必须是数字"

            return 1
            ;;

    esac


    case "$CONNECTION_MODE" in

        auto|http)
            ;;

        *)

            log "[错误] CONNECTION_MODE 只能是 auto 或 http"

            return 1
            ;;

    esac
}


start() {

    rotate_logs


    if pid=$(get_pid); then

        log "探针已经在运行。"
        log "PID=$pid"

        update_module_description

        return 0
    fi


    rm -f "$PIDFILE"


    [ -x "$BIN" ] || {

        log "[错误] 找不到探针程序：$BIN"

        return 1
    }


    validate_config ||
        return 1


    SSL_CERT_DIR="$(get_ssl_cert_dir)"


    if [ "$DEBUG" = "1" ]; then

        DEBUG_ARG="-debug=1"

    else

        DEBUG_ARG="-debug=0"
    fi


    printf '%s\n' \
        "" \
        "========================================" \
        "[管理器] $(now)" \
        "操作：启动探针" \
        "========================================" \
        "[管理器] Agent ID=$SERVER_ID" \
        "[管理器] 服务地址=$WORKER_URL" \
        "[管理器] 上报间隔=${REPORT_INTERVAL}秒" \
        "[管理器] 采集间隔=${COLLECT_INTERVAL}秒" \
        "[管理器] 连接模式=$CONNECTION_MODE" \
        "[管理器] DNS=$CF_PROBE_UPDATE_DNS_SERVER" \
        >> "$LOGFILE"


    log "正在启动探针..."


    if [ -x "$KSU_BUSYBOX" ]; then

        CF_PROBE_UPDATE_DNS="$CF_PROBE_UPDATE_DNS_SERVER" \
        SSL_CERT_DIR="$SSL_CERT_DIR" \
        "$KSU_BUSYBOX" setsid \
            "$BIN" run \
            -config="$CONFIG" \
            "$DEBUG_ARG" \
            >> "$LOGFILE" 2>&1 < /dev/null &

    else

        CF_PROBE_UPDATE_DNS="$CF_PROBE_UPDATE_DNS_SERVER" \
        SSL_CERT_DIR="$SSL_CERT_DIR" \
        nohup \
            "$BIN" run \
            -config="$CONFIG" \
            "$DEBUG_ARG" \
            >> "$LOGFILE" 2>&1 < /dev/null &
    fi


    pid=$!


    sleep 2


    if pid_alive "$pid"; then

        printf '%s\n' "$pid" > "$PIDFILE"

        log "启动成功。"
        log "PID=$pid"

        update_module_description

        return 0
    fi


    fallback_pid=$(find_probe_pid)


    if [ -n "$fallback_pid" ] &&
        pid_alive "$fallback_pid"; then

        printf '%s\n' "$fallback_pid" > "$PIDFILE"

        log "探针已启动。"
        log "PID=$fallback_pid"

        update_module_description

        return 0
    fi


    log "[错误] 探针启动失败，请查看日志。"

    update_module_description

    return 1
}


stop() {

    pid=$(get_pid 2>/dev/null || true)


    if [ -z "$pid" ]; then

        rm -f "$PIDFILE"

        log "探针已停止。"

        update_module_description

        return 0
    fi


    log "正在停止探针..."
    log "PID=$pid"


    kill "$pid" 2>/dev/null || true


    i=0


    while pid_alive "$pid"; do

        i=$((i + 1))


        if [ "$i" -ge 10 ]; then
            break
        fi


        sleep 1

    done


    if pid_alive "$pid"; then

        log "正常停止超时，正在强制结束进程..."

        kill -9 "$pid" 2>/dev/null || true

        sleep 1
    fi


    rm -f "$PIDFILE"


    # 再次检查真正的 cf-probe
    remaining=$(find_probe_pid)


    if [ -n "$remaining" ] &&
        pid_alive "$remaining"; then

        log "[错误] 探针仍然在运行。"

        update_module_description

        return 1
    fi


    log "探针已停止。"

    update_module_description

    return 0
}


restart() {

    log "正在重启探针..."


    stop ||
        return 1


    sleep 1


    start
}


toggle_debug() {

    load_config ||
        return 1


    case "$DEBUG" in

        1)
            NEW_DEBUG=0
            ;;

        *)
            NEW_DEBUG=1
            ;;

    esac


    sed \
        -i \
        "s/^DEBUG=.*/DEBUG=\"$NEW_DEBUG\"/" \
        "$CONFIG"


    if ! grep -q '^DEBUG=' "$CONFIG"; then

        printf '\nDEBUG="%s"\n' \
            "$NEW_DEBUG" \
            >> "$CONFIG"
    fi


    if [ "$NEW_DEBUG" = "1" ]; then

        log "调试日志已开启。"

    else

        log "调试日志已关闭。"
    fi


    if is_running; then

        restart

    else

        update_module_description
    fi
}


status() {

    echo "========== 当前状态 =========="


    if pid=$(get_pid); then

        echo "运行状态：运行中"
        echo "进程 PID：$pid"

    else

        echo "运行状态：已停止"
        echo "进程 PID：无"
    fi


    echo


    if [ -f "$CONFIG" ]; then

        # shellcheck disable=SC1090
        . "$CONFIG" 2>/dev/null || true


        echo "========== 当前配置 =========="

        echo "配置文件：$CONFIG"

        echo "Server ID：${SERVER_ID:-未设置}"

        echo "Worker URL：${WORKER_URL:-未设置}"

        echo "上报间隔：${REPORT_INTERVAL:-60} 秒"

        echo "采集间隔：${COLLECT_INTERVAL:-0} 秒"

        echo "连接模式：${CONNECTION_MODE:-auto}"


        if [ "${DEBUG:-0}" = "1" ]; then

            echo "调试日志：开启"

        else

            echo "调试日志：关闭"
        fi


        echo "日志最大大小：${LOG_MAX_SIZE_MB:-5} MB"

        echo "日志保留数量：${LOG_KEEP_COUNT:-3} 个"

    else

        echo "配置文件不存在：$CONFIG"
    fi


    echo


    echo "========== 日志统计 =========="


    if [ -f "$LOGFILE" ]; then

        success_count=$(
            grep \
                -c \
                'report response http=200' \
                "$LOGFILE" \
                2>/dev/null
        )


        fail_count=$(
            grep \
                -c \
                'report failed:' \
                "$LOGFILE" \
                2>/dev/null
        )


        dns_fail_count=$(
            grep \
                -c \
                'connection refused\|no ip4 addresses resolved\|no ip6 addresses resolved' \
                "$LOGFILE" \
                2>/dev/null
        )


        tls_fail_count=$(
            grep \
                -c \
                'certificate signed by unknown authority' \
                "$LOGFILE" \
                2>/dev/null
        )


        last_report=$(
            grep \
                -E \
                'report response http=|report failed:' \
                "$LOGFILE" \
                2>/dev/null |
            tail -n 1
        )


        log_size=$(get_file_size "$LOGFILE")


        echo "上报成功次数：${success_count:-0}"
        echo "上报失败次数：${fail_count:-0}"
        echo "DNS 解析异常次数：${dns_fail_count:-0}"
        echo "TLS 证书异常次数：${tls_fail_count:-0}"
        echo "当前日志大小：$((log_size / 1024)) KB"


        if [ -n "$last_report" ]; then

            echo "最近一次上报：$last_report"

        else

            echo "最近一次上报：暂无记录"
        fi

    else

        echo "暂无日志。"
    fi


    echo

    update_module_description
}


logs() {

    rotate_logs


    if [ -f "$LOGFILE" ]; then

        tail -n 150 "$LOGFILE"

    else

        log "暂无日志。"
    fi
}


case "${1:-}" in

    start)
        start
        ;;

    stop)
        stop
        ;;

    restart)
        restart
        ;;

    status)
        status
        ;;

    logs)
        logs
        ;;

    clear-logs)
        clear_logs
        ;;

    toggle-debug)
        toggle_debug
        ;;

    *)
        echo "用法："
        echo "$0 start"
        echo "$0 stop"
        echo "$0 restart"
        echo "$0 status"
        echo "$0 logs"
        echo "$0 clear-logs"
        echo "$0 toggle-debug"
        exit 2
        ;;

esac