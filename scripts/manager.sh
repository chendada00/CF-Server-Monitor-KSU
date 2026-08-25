#!/system/bin/sh

MODDIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

BIN="$MODDIR/bin/cf-probe"

DATADIR="/data/adb/cf-server-monitor"
CONFIG="$DATADIR/config.conf"
DEFAULT_CONFIG="$MODDIR/config/config.conf"

PIDFILE="$DATADIR/cf-probe.pid"

LOGDIR="$DATADIR/logs"
LOGFILE="$LOGDIR/cf-probe.log"

KSU_BUSYBOX="/data/adb/ksu/bin/busybox"

CF_PROBE_UPDATE_DNS_SERVER="223.5.5.5"


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
        chmod 600 "$CONFIG" 2>/dev/null || true
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

    CONFIG_MD5="${CONFIG_MD5:-none}"

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

    case "$LOG_MAX_SIZE_MB" in
        ''|*[!0-9]*)
            log "[错误] LOG_MAX_SIZE_MB 必须是数字"
            return 1
            ;;
    esac

    case "$LOG_KEEP_COUNT" in
        ''|*[!0-9]*)
            log "[错误] LOG_KEEP_COUNT 必须是数字"
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

    cmdline=$(tr '\000' ' ' < "/proc/$pid/cmdline" 2>/dev/null)

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

    # 第一优先级：PID 文件
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

    # PID 文件失效时重新扫描真实进程
    pid=$(find_probe_pid 2>/dev/null || true)

    if [ -n "$pid" ] && pid_alive "$pid"; then

        printf '%s\n' "$pid" > "$PIDFILE"

        printf '%s\n' "$pid"

        return 0
    fi

    rm -f "$PIDFILE"

    return 1
}


is_running() {
    get_pid >/dev/null 2>&1
}


get_probe_cmdline() {

    pid=$(get_pid 2>/dev/null || true)

    if [ -z "$pid" ]; then
        return 1
    fi

    tr '\000' ' ' < "/proc/$pid/cmdline" 2>/dev/null
}


get_runtime_debug() {

    cmdline=$(get_probe_cmdline 2>/dev/null || true)

    case "$cmdline" in

        *"-debug=1"*)
            printf '1'
            ;;

        *"-debug=0"*)
            printf '0'
            ;;

        *)
            printf 'unknown'
            ;;

    esac
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


#
# 更新 KernelSU 模块 description。
#
# 注意：
# status() 绝对不会调用这个函数。
#
# 只在 start / stop / restart / toggle-debug
# 等真正发生状态变化的操作之后调用。
#
# 并且放到后台执行，避免 KernelSU CLI 卡住 WebUI。
#
update_module_description() {

    (
        sleep 0.1

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

    ) >/dev/null 2>&1 &
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

    echo "CONFIG_MD5=$CONFIG_MD5"

    echo "DEBUG=$DEBUG"

    echo "LOG_MAX_SIZE_MB=$LOG_MAX_SIZE_MB"
    echo "LOG_KEEP_COUNT=$LOG_KEEP_COUNT"
}


#
# 给配置值做 shell 安全转义。
#
escape_config_value() {

    printf '%s' "$1" |
        sed \
            's/\\/\\\\/g; s/"/\\"/g'
}


#
# 只修改一个 key。
#
# 不重新构建整个 config.conf。
#
# 因此：
#
# CT_NODE
# CU_NODE
# CM_NODE
# BD_NODE
# INTERFACE
# RESET_DAY
# AUTO_UPDATE
# UPDATE_PROXY
# CONFIG_MD5
#
# 等其他字段都不会因为 WebUI 保存而丢失。
#
set_config_value() {

    key="$1"
    value="$2"

    tmp="$CONFIG.tmp.$$"

    escaped=$(escape_config_value "$value")

    awk \
        -v key="$key" \
        -v value="$escaped" '

        BEGIN {
            found = 0
        }

        $0 ~ ("^[[:space:]]*" key "[[:space:]]*=") {

            print key "=\"" value "\""

            found = 1

            next
        }

        {
            print
        }

        END {

            if (!found) {
                print key "=\"" value "\""
            }
        }

    ' "$CONFIG" > "$tmp" || {

        rm -f "$tmp"

        return 1
    }

    chmod 600 "$tmp" 2>/dev/null || true

    mv "$tmp" "$CONFIG" || {

        rm -f "$tmp"

        return 1
    }

    return 0
}


save_config() {

    encoded="$1"

    if [ -z "$encoded" ]; then
        log "[错误] 没有收到配置数据"
        return 1
    fi

    init_config || return 1


    decoded=$(
        printf '%s' "$encoded" |
        base64 -d 2>/dev/null
    )


    if [ -z "$decoded" ]; then
        log "[错误] 配置数据 Base64 解码失败"
        return 1
    fi


    #
    # 保存之前先备份。
    #
    backup="$CONFIG.bak"

    cp "$CONFIG" "$backup" 2>/dev/null || true


    while IFS='=' read -r key value; do

        case "$key" in

            SERVER_ID|SECRET|WORKER_URL|\
            COLLECT_INTERVAL|REPORT_INTERVAL|\
            CT_NODE|CU_NODE|CM_NODE|BD_NODE|\
            INTERFACE|RESET_DAY|\
            CONNECTION_MODE|AUTO_UPDATE|UPDATE_PROXY|\
            DEBUG|LOG_MAX_SIZE_MB|LOG_KEEP_COUNT)

                set_config_value "$key" "$value" || {

                    log "[错误] 写入配置失败：$key"

                    cp "$backup" "$CONFIG" 2>/dev/null || true

                    return 1
                }

                ;;

        esac

    done <<EOF
$decoded
EOF


    chmod 600 "$CONFIG" 2>/dev/null || true


    #
    # 保存完成后重新读取，确认 REPORT_INTERVAL 等字段
    # 真正进入了配置文件。
    #
    load_config || {

        log "[错误] 保存后重新读取配置失败"

        cp "$backup" "$CONFIG" 2>/dev/null || true

        return 1
    }


    #
    # 二次确认。
    #
    if [ -z "$REPORT_INTERVAL" ]; then
        log "[错误] REPORT_INTERVAL 保存后为空"

        cp "$backup" "$CONFIG" 2>/dev/null || true

        return 1
    fi


    rm -f "$backup"


    echo "配置保存成功。"
    echo "配置文件：$CONFIG"
    echo "REPORT_INTERVAL=$REPORT_INTERVAL"
    echo "COLLECT_INTERVAL=$COLLECT_INTERVAL"
    echo "DEBUG=$DEBUG"

    return 0
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
    manager_log "PIDFILE=$PIDFILE"
    manager_log "REPORT_INTERVAL=$REPORT_INTERVAL"
    manager_log "COLLECT_INTERVAL=$COLLECT_INTERVAL"
    manager_log "CONNECTION_MODE=$CONNECTION_MODE"
    manager_log "DEBUG=$DEBUG"
    manager_log "DEBUG_ARG=$DEBUG_ARG"
    manager_log "========================================"


    log "正在启动探针..."
    log "Debug=$DEBUG"
    log "启动参数=$DEBUG_ARG"


    #
    # 使用独立 session。
    #
    # 不把 cf-probe 绑定在 WebUI 进程上。
    #
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
        setsid \
            "$BIN" run \
            -config="$CONFIG" \
            "$DEBUG_ARG" \
            >> "$LOGFILE" 2>&1 < /dev/null &

    fi


    #
    # 不相信 $! 就是 cf-probe PID。
    #
    # Android / BusyBox 的 setsid 实现可能返回 wrapper PID。
    #
    # 所以启动后扫描真实 cf-probe。
    #
    count=0

    while [ "$count" -lt 10 ]; do

        sleep 1

        pid=$(find_probe_pid 2>/dev/null || true)

        if [ -n "$pid" ] &&
            pid_alive "$pid"; then

            printf '%s\n' "$pid" > "$PIDFILE"

            runtime_debug=$(get_runtime_debug)

            log "启动成功。"
            log "PID=$pid"
            log "实际 Debug=$runtime_debug"

            update_module_description

            return 0
        fi

        count=$((count + 1))
    done


    log "[错误] cf-probe 启动失败。"
    log "请查看日志：$LOGFILE"

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

    while [ "$count" -lt 10 ]; do

        if ! pid_alive "$pid"; then
            break
        fi

        sleep 1

        count=$((count + 1))
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


    if ! start; then

        log "[错误] 新进程启动失败。"

        return 1
    fi


    pid=$(get_pid 2>/dev/null || true)


    if [ -z "$pid" ]; then

        log "[错误] 重启后无法找到 cf-probe PID。"

        return 1
    fi


    runtime_debug=$(get_runtime_debug)


    log "重启成功。"
    log "新 PID=$pid"
    log "实际 Debug=$runtime_debug"


    update_module_description

    return 0
}


toggle_debug() {

    load_config || return 1


    if [ "$DEBUG" = "1" ]; then
        NEW_DEBUG="0"
    else
        NEW_DEBUG="1"
    fi


    if ! set_config_value "DEBUG" "$NEW_DEBUG"; then

        log "[错误] 无法修改 DEBUG"

        return 1
    fi


    chmod 600 "$CONFIG" 2>/dev/null || true


    log "配置 DEBUG=$NEW_DEBUG"


    if is_running; then

        log "正在重启 cf-probe 使 Debug 立即生效..."


        if ! restart; then
            return 1
        fi


        runtime_debug=$(get_runtime_debug)


        if [ "$runtime_debug" = "$NEW_DEBUG" ]; then

            log "Debug 已生效。"
            log "实际进程参数：$(get_probe_cmdline)"

        else

            log "[警告] 配置 DEBUG=$NEW_DEBUG"
            log "[警告] 但实际进程 Debug=$runtime_debug"
            log "实际进程参数：$(get_probe_cmdline)"
        fi

    else

        log "当前探针未运行。"
        log "Debug 配置已保存，下次启动时生效。"

        update_module_description
    fi


    return 0
}


show_logs() {

    rotate_logs

    if [ -f "$LOGFILE" ]; then

        tail -n 200 "$LOGFILE"

    else

        log "暂无日志。"
    fi
}


clear_logs() {

    : > "$LOGFILE"

    i=1

    while [ "$i" -le 20 ]; do
        rm -f "$LOGFILE.$i"
        i=$((i + 1))
    done

    log "日志已清空。"
}


status() {

    #
    # 非常重要：
    #
    # status 只负责查询。
    #
    # 这里绝对不调用 update_module_description。
    #
    # 否则 WebUI 每几秒刷新一次状态都会触发 ksud。
    #


    echo "========== CF Server Monitor =========="

    echo "配置文件：$CONFIG"


    if pid=$(get_pid 2>/dev/null); then

        echo "运行状态：运行中"
        echo "进程 PID：$pid"

        cmdline=$(get_probe_cmdline 2>/dev/null || true)

        echo "进程参数：${cmdline:-未知}"

        runtime_debug=$(get_runtime_debug)

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
        echo "实际 Debug：无"

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
        get_runtime_debug
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