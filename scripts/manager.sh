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


manager_log() {
    printf '[%s] %s\n' "$(now)" "$*" >> "$LOGFILE"
}


init_config() {

    mkdir -p "$DATADIR" "$LOGDIR"

    if [ -f "$CONFIG" ]; then
        return 0
    fi

    if [ ! -f "$DEFAULT_CONFIG" ]; then
        log "[错误] 默认配置不存在：$DEFAULT_CONFIG"
        return 1
    fi

    cp "$DEFAULT_CONFIG" "$CONFIG" || {
        log "[错误] 无法创建配置文件：$CONFIG"
        return 1
    }

    chmod 600 "$CONFIG" 2>/dev/null || true

    return 0
}


load_config() {

    init_config || return 1

    if [ ! -r "$CONFIG" ]; then
        log "[错误] 配置文件不可读：$CONFIG"
        return 1
    fi

    # shellcheck disable=SC1090
    . "$CONFIG" 2>/dev/null || {
        log "[错误] 配置文件格式错误：$CONFIG"
        return 1
    }

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

    LOG_MAX_SIZE_MB="${LOG_MAX_SIZE_MB:-5}"
    LOG_KEEP_COUNT="${LOG_KEEP_COUNT:-3}"

    return 0
}


validate_config() {

    load_config || return 1

    if [ -z "$SERVER_ID" ]; then
        log "[错误] SERVER_ID 不能为空"
        return 1
    fi

    if [ -z "$SECRET" ]; then
        log "[错误] SECRET 不能为空"
        return 1
    fi

    if [ -z "$WORKER_URL" ]; then
        log "[错误] WORKER_URL 不能为空"
        return 1
    fi

    case "$COLLECT_INTERVAL" in
        ''|*[!0-9]*)
            log "[错误] COLLECT_INTERVAL 必须是数字"
            return 1
            ;;
    esac

    case "$REPORT_INTERVAL" in
        ''|*[!0-9]*)
            log "[错误] REPORT_INTERVAL 必须是数字"
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

    case "$DEBUG" in
        0|1)
            ;;
        *)
            log "[错误] DEBUG 只能是 0 或 1"
            return 1
            ;;
    esac

    return 0
}


get_ssl_cert_dir() {

    if [ -d "/apex/com.android.conscrypt/cacerts" ]; then
        printf '%s' "/apex/com.android.conscrypt/cacerts"
        return
    fi

    if [ -d "/system/etc/security/cacerts" ]; then
        printf '%s' "/system/etc/security/cacerts"
        return
    fi

    printf '%s' ""
}


pid_alive() {

    pid="$1"

    [ -n "$pid" ] || return 1

    case "$pid" in
        ''|*[!0-9]*)
            return 1
            ;;
    esac

    [ "$pid" -gt 0 ] || return 1

    [ -r "/proc/$pid/cmdline" ] || return 1

    cmdline=$(
        tr '\000' ' ' < "/proc/$pid/cmdline" 2>/dev/null
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

    pid=""

    if [ -x "$KSU_BUSYBOX" ]; then
        pid=$(
            "$KSU_BUSYBOX" pgrep -f "$BIN" 2>/dev/null |
            head -n 1
        )
    fi

    if [ -z "$pid" ]; then
        pid=$(
            pidof cf-probe 2>/dev/null |
            awk '{print $1}'
        )
    fi

    if [ -n "$pid" ] && pid_alive "$pid"; then
        printf '%s\n' "$pid"
        return 0
    fi

    return 1
}


get_pid() {

    if [ -f "$PIDFILE" ]; then

        pid=$(cat "$PIDFILE" 2>/dev/null)

        case "$pid" in
            ''|*[!0-9]*)
                pid=""
                ;;
        esac

        if [ -n "$pid" ] && pid_alive "$pid"; then
            printf '%s\n' "$pid"
            return 0
        fi
    fi

    pid=$(find_probe_pid 2>/dev/null || true)

    if [ -n "$pid" ] && pid_alive "$pid"; then
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

    if [ ! -f "$file" ]; then
        printf '0'
        return
    fi

    wc -c < "$file" 2>/dev/null |
        tr -d ' '
}


rotate_logs() {

    load_config >/dev/null 2>&1 || return 0

    [ -f "$LOGFILE" ] || return 0

    case "$LOG_MAX_SIZE_MB" in
        ''|*[!0-9]*)
            return 0
            ;;
    esac

    [ "$LOG_MAX_SIZE_MB" -gt 0 ] 2>/dev/null || return 0

    current_size=$(get_file_size "$LOGFILE")

    max_bytes=$(
        awk -v mb="$LOG_MAX_SIZE_MB" \
            'BEGIN { print mb * 1024 * 1024 }'
    )

    [ "$current_size" -ge "$max_bytes" ] 2>/dev/null || return 0

    keep="$LOG_KEEP_COUNT"

    case "$keep" in
        ''|*[!0-9]*)
            keep=3
            ;;
    esac

    [ "$keep" -gt 0 ] 2>/dev/null || keep=3

    i="$keep"

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


update_module_description() {

    pid=$(get_pid 2>/dev/null || true)

    if [ -n "$pid" ]; then
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
        else
            desc="$desc | 调试已关闭"
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


show_config() {

    load_config || return 1

    echo "CONFIG_FILE=$CONFIG"

    echo "SERVER_ID=$SERVER_ID"
    echo "SECRET=$SECRET"
    echo "WORKER_URL=$WORKER_URL"

    echo "COLLECT_INTERVAL=$COLLECT_INTERVAL"
    echo "REPORT_INTERVAL=$REPORT_INTERVAL"

    echo "CT_NODE=$CT_NODE"
    echo "CU_NODE=$CU_NODE"
    echo "CM_NODE=$CM_NODE"
    echo "BD_NODE=$BD_NODE"

    echo "INTERFACE=$INTERFACE"
    echo "RESET_DAY=$RESET_DAY"

    echo "CONNECTION_MODE=$CONNECTION_MODE"

    echo "AUTO_UPDATE=$AUTO_UPDATE"
    echo "UPDATE_PROXY=$UPDATE_PROXY"

    echo "DEBUG=$DEBUG"

    echo "LOG_MAX_SIZE_MB=$LOG_MAX_SIZE_MB"
    echo "LOG_KEEP_COUNT=$LOG_KEEP_COUNT"
}


save_config() {

    encoded="$1"

    if [ -z "$encoded" ]; then
        log "[错误] 没有收到配置数据"
        return 1
    fi

    mkdir -p "$DATADIR"

    tmp="$CONFIG.tmp.$$"

    decoded=$(
        printf '%s' "$encoded" |
        base64 -d 2>/dev/null
    )

    if [ -z "$decoded" ]; then
        log "[错误] 配置数据解析失败"
        return 1
    fi

    SERVER_ID=""
    SECRET=""
    WORKER_URL=""

    COLLECT_INTERVAL="0"
    REPORT_INTERVAL="60"

    CONNECTION_MODE="auto"
    DEBUG="0"

    LOG_MAX_SIZE_MB="5"
    LOG_KEEP_COUNT="3"

    CT_NODE=""
    CU_NODE=""
    CM_NODE=""
    BD_NODE=""

    INTERFACE=""
    RESET_DAY="1"

    AUTO_UPDATE="0"
    UPDATE_PROXY=""


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


    case "$COLLECT_INTERVAL" in
        ''|*[!0-9]*)
            log "[错误] COLLECT_INTERVAL 必须是数字"
            return 1
            ;;
    esac

    case "$REPORT_INTERVAL" in
        ''|*[!0-9]*)
            log "[错误] REPORT_INTERVAL 必须是数字"
            return 1
            ;;
    esac

    case "$CONNECTION_MODE" in
        auto|http)
            ;;
        *)
            log "[错误] CONNECTION_MODE 无效"
            return 1
            ;;
    esac

    case "$DEBUG" in
        0|1)
            ;;
        *)
            log "[错误] DEBUG 无效"
            return 1
            ;;
    esac

    case "$LOG_MAX_SIZE_MB" in
        ''|*[!0-9]*)
            LOG_MAX_SIZE_MB="5"
            ;;
    esac

    case "$LOG_KEEP_COUNT" in
        ''|*[!0-9]*)
            LOG_KEEP_COUNT="3"
            ;;
    esac


    if [ -z "$SERVER_ID" ]; then
        log "[错误] SERVER_ID 不能为空"
        return 1
    fi

    if [ -z "$SECRET" ]; then
        log "[错误] SECRET 不能为空"
        return 1
    fi

    if [ -z "$WORKER_URL" ]; then
        log "[错误] WORKER_URL 不能为空"
        return 1
    fi


    {
        printf '%s\n' '# CF Server Monitor Android / KernelSU 配置'

        printf 'SERVER_ID=%s\n' "$(printf '%s' "$SERVER_ID" | sed 's/"/\\"/g' | sed 's/^/"/;s/$/"/')"

        printf 'SECRET=%s\n' "$(printf '%s' "$SECRET" | sed 's/"/\\"/g' | sed 's/^/"/;s/$/"/')"

        printf 'WORKER_URL=%s\n' "$(printf '%s' "$WORKER_URL" | sed 's/"/\\"/g' | sed 's/^/"/;s/$/"/')"

        printf 'COLLECT_INTERVAL="%s"\n' "$COLLECT_INTERVAL"
        printf 'REPORT_INTERVAL="%s"\n' "$REPORT_INTERVAL"

        printf 'CT_NODE="%s"\n' "$CT_NODE"
        printf 'CU_NODE="%s"\n' "$CU_NODE"
        printf 'CM_NODE="%s"\n' "$CM_NODE"
        printf 'BD_NODE="%s"\n' "$BD_NODE"

        printf 'INTERFACE="%s"\n' "$INTERFACE"
        printf 'RESET_DAY="%s"\n' "$RESET_DAY"

        printf 'CONNECTION_MODE="%s"\n' "$CONNECTION_MODE"

        printf 'AUTO_UPDATE="%s"\n' "$AUTO_UPDATE"
        printf 'UPDATE_PROXY="%s"\n' "$UPDATE_PROXY"

        printf 'CONFIG_MD5="%s"\n' "none"

        printf 'DEBUG="%s"\n' "$DEBUG"

        printf 'LOG_MAX_SIZE_MB="%s"\n' "$LOG_MAX_SIZE_MB"
        printf 'LOG_KEEP_COUNT="%s"\n' "$LOG_KEEP_COUNT"

    } > "$tmp" || {

        rm -f "$tmp"

        log "[错误] 无法写入配置"

        return 1
    }


    chmod 600 "$tmp" 2>/dev/null || true

    mv "$tmp" "$CONFIG" || {

        rm -f "$tmp"

        log "[错误] 无法替换配置文件"

        return 1
    }


    log "OK"
    log "配置保存成功。"

    return 0
}


get_probe_cmdline() {

    pid=$(get_pid 2>/dev/null || true)

    if [ -z "$pid" ]; then
        return 1
    fi

    tr '\000' ' ' \
        < "/proc/$pid/cmdline" \
        2>/dev/null
}


get_debug_runtime() {

    cmdline=$(get_probe_cmdline 2>/dev/null || true)

    case "$cmdline" in

        *"-debug=1"*)
            printf '%s' "1"
            ;;

        *"-debug=0"*)
            printf '%s' "0"
            ;;

        *)
            printf '%s' "unknown"
            ;;

    esac
}


start() {

    rotate_logs

    if pid=$(get_pid 2>/dev/null); then

        log "探针已经在运行。"
        log "PID=$pid"

        update_module_description

        return 0
    fi


    rm -f "$PIDFILE"


    if [ ! -x "$BIN" ]; then

        log "[错误] 找不到探针程序：$BIN"

        update_module_description

        return 1
    fi


    validate_config || {

        update_module_description

        return 1
    }


    SSL_CERT_DIR="$(get_ssl_cert_dir)"


    if [ "$DEBUG" = "1" ]; then
        DEBUG_ARG="-debug=1"
    else
        DEBUG_ARG="-debug=0"
    fi


    manager_log "========================================"
    manager_log "启动 cf-probe"
    manager_log "CONFIG=$CONFIG"
    manager_log "SERVER_ID=$SERVER_ID"
    manager_log "WORKER_URL=$WORKER_URL"
    manager_log "COLLECT_INTERVAL=$COLLECT_INTERVAL"
    manager_log "REPORT_INTERVAL=$REPORT_INTERVAL"
    manager_log "CONNECTION_MODE=$CONNECTION_MODE"
    manager_log "DEBUG=$DEBUG"
    manager_log "DEBUG_ARG=$DEBUG_ARG"
    manager_log "========================================"


    log "正在启动探针..."
    log "Debug=$DEBUG"
    log "启动参数=$DEBUG_ARG"


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


    launch_pid=$!


    sleep 2


    if pid_alive "$launch_pid"; then

        printf '%s\n' "$launch_pid" > "$PIDFILE"

        runtime_debug=$(get_debug_runtime 2>/dev/null || true)

        log "启动成功。"
        log "PID=$launch_pid"
        log "实际 Debug=$runtime_debug"

        update_module_description

        return 0
    fi


    fallback_pid=$(find_probe_pid 2>/dev/null || true)


    if [ -n "$fallback_pid" ] &&
        pid_alive "$fallback_pid"; then

        printf '%s\n' "$fallback_pid" > "$PIDFILE"

        runtime_debug=$(get_debug_runtime 2>/dev/null || true)

        log "启动成功。"
        log "PID=$fallback_pid"
        log "实际 Debug=$runtime_debug"

        update_module_description

        return 0
    fi


    log "[错误] cf-probe 启动失败。"
    log "请查看：$LOGFILE"

    update_module_description

    return 1
}


stop() {

    pid=$(get_pid 2>/dev/null || true)


    if [ -z "$pid" ]; then

        rm -f "$PIDFILE"

        log "探针已经停止。"

        update_module_description

        return 0
    fi


    log "正在停止探针..."
    log "PID=$pid"


    kill "$pid" 2>/dev/null || true


    count=0

    while pid_alive "$pid"; do

        count=$((count + 1))

        if [ "$count" -ge 10 ]; then
            break
        fi

        sleep 1
    done


    if pid_alive "$pid"; then

        log "正常停止超时，执行 SIGKILL..."

        kill -9 "$pid" 2>/dev/null || true

        sleep 1
    fi


    rm -f "$PIDFILE"


    remaining=$(find_probe_pid 2>/dev/null || true)


    if [ -n "$remaining" ] &&
        pid_alive "$remaining"; then

        log "[错误] cf-probe 仍在运行。PID=$remaining"

        printf '%s\n' "$remaining" > "$PIDFILE"

        update_module_description

        return 1
    fi


    log "探针已停止。"

    update_module_description

    return 0
}


restart() {

    log "正在重启探针..."

    if ! stop; then
        log "[错误] 停止旧进程失败。"
        return 1
    fi

    sleep 1

    start
}


toggle_debug() {

    load_config || return 1


    if [ "$DEBUG" = "1" ]; then
        NEW_DEBUG="0"
    else
        NEW_DEBUG="1"
    fi


    tmp="$CONFIG.tmp.$$"


    sed \
        "s/^DEBUG=.*/DEBUG=\"$NEW_DEBUG\"/" \
        "$CONFIG" > "$tmp"


    if ! grep -q '^DEBUG=' "$tmp"; then
        printf '\nDEBUG="%s"\n' "$NEW_DEBUG" >> "$tmp"
    fi


    mv "$tmp" "$CONFIG" || {

        rm -f "$tmp"

        log "[错误] 无法修改 DEBUG"

        return 1
    }


    chmod 600 "$CONFIG" 2>/dev/null || true


    log "配置 DEBUG=$NEW_DEBUG"


    if is_running; then

        log "正在重启 cf-probe 使 Debug 配置立即生效..."

        if ! restart; then
            return 1
        fi

    else

        log "当前探针未运行，仅修改配置。"

        update_module_description
    fi


    runtime_debug=$(get_debug_runtime 2>/dev/null || true)


    if is_running; then

        if [ "$runtime_debug" = "$NEW_DEBUG" ]; then

            log "Debug 已生效。"
            log "实际进程参数：$(get_probe_cmdline)"

        else

            log "[警告] 配置 DEBUG=$NEW_DEBUG，但实际进程 Debug=$runtime_debug"

            log "实际进程参数：$(get_probe_cmdline)"
        fi

    fi


    return 0
}


clear_logs() {

    : > "$LOGFILE"

    rm -f "$LOGFILE".[0-9]*

    log "日志已清空。"

    update_module_description
}


show_logs() {

    rotate_logs

    if [ -f "$LOGFILE" ]; then
        tail -n 200 "$LOGFILE"
    else
        log "暂无日志。"
    fi
}


status() {

    echo "========== CF Server Monitor =========="

    echo "配置文件：$CONFIG"


    if pid=$(get_pid 2>/dev/null); then

        echo "运行状态：运行中"
        echo "进程 PID：$pid"

        cmdline=$(get_probe_cmdline 2>/dev/null || true)

        echo "进程参数：${cmdline:-未知}"

        runtime_debug=$(get_debug_runtime 2>/dev/null || true)

        case "$runtime_debug" in
            1)
                echo "实际 Debug：开启"
                ;;
            0)
                echo "实际 Debug：关闭"
                ;;
            *)
                echo "实际 Debug：未知"
                ;;
        esac

    else

        echo "运行状态：已停止"
        echo "进程 PID：无"

    fi


    echo


    if load_config >/dev/null 2>&1; then

        echo "========== 当前配置 =========="

        echo "Server ID：${SERVER_ID:-未设置}"
        echo "Worker URL：${WORKER_URL:-未设置}"
        echo "上报间隔：${REPORT_INTERVAL:-60} 秒"
        echo "采集间隔：${COLLECT_INTERVAL:-0} 秒"
        echo "连接模式：${CONNECTION_MODE:-auto}"

        if [ "${DEBUG:-0}" = "1" ]; then
            echo "配置 Debug：开启"
        else
            echo "配置 Debug：关闭"
        fi

        echo "日志最大大小：${LOG_MAX_SIZE_MB:-5} MB"
        echo "日志保留数量：${LOG_KEEP_COUNT:-3} 个"

    else

        echo "配置读取失败。"

    fi


    echo


    echo "========== 日志统计 =========="


    if [ -f "$LOGFILE" ]; then

        success_count=$(
            grep -c \
                'report response http=200' \
                "$LOGFILE" \
                2>/dev/null
        )

        fail_count=$(
            grep -c \
                'report failed:' \
                "$LOGFILE" \
                2>/dev/null
        )

        dns_fail_count=$(
            grep -c \
                'connection refused\|no ip4 addresses resolved\|no ip6 addresses resolved' \
                "$LOGFILE" \
                2>/dev/null
        )

        tls_fail_count=$(
            grep -c \
                'certificate signed by unknown authority' \
                "$LOGFILE" \
                2>/dev/null
        )

        log_size=$(get_file_size "$LOGFILE")

        last_report=$(
            grep \
                -E \
                'report response http=|report failed:' \
                "$LOGFILE" \
                2>/dev/null |
            tail -n 1
        )

        echo "上报成功次数：${success_count:-0}"
        echo "上报失败次数：${fail_count:-0}"
        echo "DNS 异常次数：${dns_fail_count:-0}"
        echo "TLS 异常次数：${tls_fail_count:-0}"
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

        show_logs
        ;;

    clear-logs)

        clear_logs
        ;;

    toggle-debug)

        toggle_debug
        ;;

    get-config)

        show_config
        ;;

    save-config)

        save_config "${2:-}"
        ;;

    runtime-debug)

        get_debug_runtime
        ;;

    pid)

        get_pid
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
        echo "$0 get-config"
        echo "$0 save-config BASE64"
        echo "$0 runtime-debug"
        echo "$0 pid"

        exit 2
        ;;

esac