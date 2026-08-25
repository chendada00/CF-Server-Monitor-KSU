#!/system/bin/sh

MODDIR="${0%/*}"
MODDIR="${MODDIR%/*}"

DATA_DIR="/data/adb/cf-server-monitor"

BIN="$MODDIR/bin/cf-probe"
DEFAULT_CONFIG="$MODDIR/config/config.conf"
CONFIG="$DATA_DIR/config.conf"

PIDFILE="$DATA_DIR/cf-probe.pid"
LOGFILE="$DATA_DIR/cf-probe.log"
BOOTLOG="$DATA_DIR/boot.log"

KSU_BUSYBOX="/data/adb/ksu/bin/busybox"
# 强制探针使用公共 DNS。
# Android/KSU 环境下 /etc/resolv.conf 可能指向 [::1]:53，
# 但手机上通常没有本地 DNS 服务，因此会导致所有域名解析失败。
CF_PROBE_UPDATE_DNS_SERVER="223.5.5.5"

# Android 系统 CA 证书目录。
if [ -d "/apex/com.android.conscrypt/cacerts" ]; then
    SSL_CERT_DIR="/apex/com.android.conscrypt/cacerts"
elif [ -d "/system/etc/security/cacerts" ]; then
    SSL_CERT_DIR="/system/etc/security/cacerts"
else
    SSL_CERT_DIR=""
fi

mkdir -p "$DATA_DIR"


log() {
    echo "$*"
}

update_module_description() {

    REPORT_INTERVAL_VALUE="$(get_config_value REPORT_INTERVAL 2>/dev/null || true)"

    if [ -z "$REPORT_INTERVAL_VALUE" ]; then
        REPORT_INTERVAL_VALUE="60"
    fi

    CURRENT_PID="$(get_pid 2>/dev/null || true)"

    if [ -z "$CURRENT_PID" ]; then
        CURRENT_PID="$(find_probe_pid 2>/dev/null || true)"
    fi

    if [ -n "$CURRENT_PID" ]; then

        DESCRIPTION="● 探针运行中 | PID=$CURRENT_PID | 上报间隔=${REPORT_INTERVAL_VALUE}秒"

    else

        DESCRIPTION="● 探针已停止 | 上报间隔=${REPORT_INTERVAL_VALUE}秒"

    fi

    if [ -x "/data/adb/ksud" ]; then

        /data/adb/ksud module config set \
            override.description \
            "$DESCRIPTION" \
            >/dev/null 2>&1 || true

        return 0

    fi

    if command -v ksud >/dev/null 2>&1; then

        ksud module config set \
            override.description \
            "$DESCRIPTION" \
            >/dev/null 2>&1 || true

    fi

}
init_config() {

    if [ -f "$CONFIG" ]; then
        return 0
    fi

    if [ ! -f "$DEFAULT_CONFIG" ]; then
        log "ERROR: default config not found:"
        log "$DEFAULT_CONFIG"
        return 1
    fi

    log "Initializing config..."

    cp "$DEFAULT_CONFIG" "$CONFIG" || return 1

    chmod 600 "$CONFIG" 2>/dev/null || true

    return 0
}


get_config_value() {

    KEY="$1"

    [ -f "$CONFIG" ] || return 1

    sed -n \
        "s/^${KEY}=\"\\{0,1\\}\\([^\"\\r]*\\)\"\\{0,1\\}.*/\\1/p" \
        "$CONFIG" \
        | head -n 1

}


validate_config() {

    init_config || return 1

    SERVER_ID="$(get_config_value SERVER_ID)"
    SECRET="$(get_config_value SECRET)"
    WORKER_URL="$(get_config_value WORKER_URL)"

    if [ -z "$SERVER_ID" ]; then
        log "ERROR: SERVER_ID is empty"
        return 1
    fi

    if [ -z "$SECRET" ]; then
        log "ERROR: SECRET is empty"
        return 1
    fi

    if [ -z "$WORKER_URL" ]; then
        log "ERROR: WORKER_URL is empty"
        return 1
    fi

    case "$WORKER_URL" in
        http://*|https://*)
            ;;
        *)
            log "ERROR: WORKER_URL must start with http:// or https://"
            log "WORKER_URL=$WORKER_URL"
            return 1
            ;;
    esac

    return 0
}


pid_alive() {

    PID="$1"

    [ -n "$PID" ] || return 1

    case "$PID" in
        ''|*[!0-9]*)
            return 1
            ;;
    esac

    kill -0 "$PID" 2>/dev/null

}


pid_is_probe() {

    PID="$1"

    pid_alive "$PID" || return 1

    CMDLINE=""

    if [ -r "/proc/$PID/cmdline" ]; then

        CMDLINE="$(tr '\000' ' ' < "/proc/$PID/cmdline" 2>/dev/null)"

    fi

    case "$CMDLINE" in
        *cf-probe*)
            return 0
            ;;
    esac

    return 1

}


get_pid() {

    [ -f "$PIDFILE" ] || return 1

    PID="$(cat "$PIDFILE" 2>/dev/null)"

    case "$PID" in
        ''|*[!0-9]*)
            return 1
            ;;
    esac

    if pid_is_probe "$PID"; then

        echo "$PID"
        return 0

    fi

    rm -f "$PIDFILE"

    return 1
}


find_probe_pid() {

    if command -v pidof >/dev/null 2>&1; then

        for PID in $(pidof cf-probe 2>/dev/null); do

            if pid_is_probe "$PID"; then
                echo "$PID"
                return 0
            fi

        done

    fi

    for PROC in /proc/[0-9]*; do

        [ -r "$PROC/cmdline" ] || continue

        PID="${PROC##*/}"

        CMDLINE="$(tr '\000' ' ' < "$PROC/cmdline" 2>/dev/null)"

        case "$CMDLINE" in
            *"$BIN"*|*cf-probe*)
                echo "$PID"
                return 0
                ;;
        esac

    done

    return 1
}


append_log_header() {

    {
        echo
        echo "========================================"
        echo "[MANAGER] $(date '+%Y-%m-%d %H:%M:%S')"
        echo "ACTION=$1"
        echo "BIN=$BIN"
        echo "CONFIG=$CONFIG"
        echo "========================================"
    } >> "$LOGFILE"

}


start() {

    if ! validate_config; then
        return 1
    fi


    if PID="$(get_pid)"; then

        log "Already running."
        log "PID=$PID"

        return 0

    fi


    if PID="$(find_probe_pid)"; then

        log "Found existing cf-probe process."
        log "PID=$PID"

        echo "$PID" > "$PIDFILE"

        return 0

    fi


    if [ ! -f "$BIN" ]; then

        log "ERROR: cf-probe not found:"
        log "$BIN"

        return 1

    fi


    chmod 755 "$BIN" 2>/dev/null || true


    if [ ! -x "$BIN" ]; then

        log "ERROR: cf-probe is not executable:"
        log "$BIN"

        return 1

    fi


    append_log_header "START"

    {
        echo "[MANAGER] SERVER_ID=$SERVER_ID"
        echo "[MANAGER] WORKER_URL=$WORKER_URL"
    echo "[MANAGER] DEBUG=1"
    echo "[MANAGER] CF_PROBE_UPDATE_DNS=$CF_PROBE_UPDATE_DNS_SERVER"
    echo "[MANAGER] SSL_CERT_DIR=$SSL_CERT_DIR"

    if [ -n "$SSL_CERT_DIR" ]; then
        echo "[MANAGER] CA certificate files=$(ls "$SSL_CERT_DIR" 2>/dev/null | wc -l)"
    else
        echo "[MANAGER] WARNING: Android CA certificate directory not found"
    fi

    echo "[MANAGER] Starting probe..."
    } >> "$LOGFILE"


    log "Starting CF Server Monitor..."
    log "Server ID=$SERVER_ID"
    log "Worker URL=$WORKER_URL"
    log "Debug log=enabled"

    if [ -x "$KSU_BUSYBOX" ]; then

        CF_PROBE_UPDATE_DNS="$CF_PROBE_UPDATE_DNS_SERVER" \
        SSL_CERT_DIR="$SSL_CERT_DIR" \
            "$KSU_BUSYBOX" setsid \
            "$BIN" run \
            -config="$CONFIG" \
            -debug=1 \
            >> "$LOGFILE" 2>&1 < /dev/null &

    else

        CF_PROBE_UPDATE_DNS="$CF_PROBE_UPDATE_DNS_SERVER" \
        SSL_CERT_DIR="$SSL_CERT_DIR" \
            nohup \
            "$BIN" run \
            -config="$CONFIG" \
            -debug=1 \
            >> "$LOGFILE" 2>&1 < /dev/null &

    fi


    PID=$!


    sleep 3


    if ! pid_alive "$PID"; then

        log "ERROR: cf-probe failed to stay alive"
        log
        log "Last log:"

        tail -n 80 "$LOGFILE" 2>/dev/null

        rm -f "$PIDFILE"

        return 1

    fi


    if ! pid_is_probe "$PID"; then

        sleep 1

        if REAL_PID="$(find_probe_pid)"; then
            PID="$REAL_PID"
        fi

    fi


    echo "$PID" > "$PIDFILE"
    update_module_description

    log "Started successfully."
    log "PID=$PID"
    log
    log "Probe is running."
    log "HTTP report result must be checked in logs."


    sleep 2


    log
    log "Recent log:"
    tail -n 30 "$LOGFILE" 2>/dev/null


    return 0

}


stop() {

    PID="$(get_pid)"

    if [ -z "$PID" ]; then

        PID="$(find_probe_pid 2>/dev/null || true)"

    fi


    if [ -z "$PID" ]; then

        rm -f "$PIDFILE"

        log "Already stopped."
        update_module_description
        return 0

    fi


    log "Stopping CF Server Monitor..."
    log "PID=$PID"


    kill "$PID" 2>/dev/null || true


    COUNT=0

    while pid_alive "$PID"; do

        COUNT=$((COUNT + 1))

        if [ "$COUNT" -ge 10 ]; then
            break
        fi

        sleep 1

    done


    if pid_alive "$PID"; then

        log "Graceful stop timed out."
        log "Force killing..."

        kill -9 "$PID" 2>/dev/null || true

        sleep 1

    fi


    if pid_alive "$PID"; then

        log "ERROR: failed to stop process"

        return 1

    fi


    rm -f "$PIDFILE"


    log "Stopped."

    return 0

}


restart() {

    log "Restarting..."

    stop || return 1

    sleep 1

    start

}


status() {

    init_config >/dev/null 2>&1 || true


    PID="$(get_pid 2>/dev/null || true)"

    if [ -z "$PID" ]; then

        PID="$(find_probe_pid 2>/dev/null || true)"

        if [ -n "$PID" ]; then
            echo "$PID" > "$PIDFILE"
        fi

    fi


    if [ -n "$PID" ]; then

        echo "STATUS=RUNNING"
        echo "PID=$PID"

    else

        echo "STATUS=STOPPED"

    fi


    echo
    echo "BIN=$BIN"
    echo "CONFIG=$CONFIG"
    echo "LOG=$LOGFILE"


    if [ -f "$CONFIG" ]; then

        echo
        echo "Configuration:"

        grep -v '^SECRET=' "$CONFIG" 2>/dev/null

    else

        echo
        echo "Configuration file does not exist."

    fi


    if [ -f "$LOGFILE" ]; then

        echo
        echo "Last log lines:"

        tail -n 10 "$LOGFILE"

    fi
    update_module_description
}


logs() {

    if [ -f "$LOGFILE" ]; then

        tail -n 150 "$LOGFILE"

    else

        log "No logs yet."

    fi

}


diagnose() {

    echo "========================================"
    echo "CF Server Monitor Diagnose"
    echo "========================================"
    echo


    echo "[1] Binary"

    if [ -f "$BIN" ]; then

        ls -l "$BIN" 2>/dev/null || true

        if [ -x "$BIN" ]; then
            echo "EXECUTABLE=YES"
        else
            echo "EXECUTABLE=NO"
        fi

    else

        echo "NOT FOUND"

    fi


    echo
    echo "[2] Version"

    if [ -x "$BIN" ]; then

        "$BIN" version 2>&1 || true

    fi


    echo
    echo "[3] Process"

    PID="$(get_pid 2>/dev/null || true)"

    if [ -z "$PID" ]; then
        PID="$(find_probe_pid 2>/dev/null || true)"
    fi

    if [ -n "$PID" ]; then

        echo "RUNNING"
        echo "PID=$PID"

        if [ -r "/proc/$PID/cmdline" ]; then

            echo "CMDLINE:"
            tr '\000' ' ' < "/proc/$PID/cmdline"
            echo

        fi

    else

        echo "STOPPED"

    fi


    echo
    echo "[4] Configuration"

    if [ -f "$CONFIG" ]; then

        SERVER_ID="$(get_config_value SERVER_ID)"
        WORKER_URL="$(get_config_value WORKER_URL)"
        REPORT_INTERVAL="$(get_config_value REPORT_INTERVAL)"
        CONNECTION_MODE="$(get_config_value CONNECTION_MODE)"

        echo "SERVER_ID=$SERVER_ID"
        echo "WORKER_URL=$WORKER_URL"
        echo "REPORT_INTERVAL=$REPORT_INTERVAL"
        echo "CONNECTION_MODE=$CONNECTION_MODE"

        if [ -n "$SERVER_ID" ]; then
            echo "SERVER_ID=OK"
        else
            echo "SERVER_ID=EMPTY"
        fi

        if [ -n "$(get_config_value SECRET)" ]; then
            echo "SECRET=SET"
        else
            echo "SECRET=EMPTY"
        fi

        if [ -n "$WORKER_URL" ]; then
            echo "WORKER_URL=SET"
        else
            echo "WORKER_URL=EMPTY"
        fi

    else

        echo "CONFIG NOT FOUND"

    fi


    echo
    echo "[5] Network"

    getprop sys.boot_completed 2>/dev/null | sed 's/^/sys.boot_completed=/'

    if command -v ping >/dev/null 2>&1; then

        ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1 \
            && echo "IPv4 network=OK" \
            || echo "IPv4 network=FAILED"

    fi


    echo
    echo "[6] Latest Probe Log"

    if [ -f "$LOGFILE" ]; then

        tail -n 80 "$LOGFILE"

    else

        echo "NO LOG"

    fi

}


version() {

    if [ -x "$BIN" ]; then

        "$BIN" version

    else

        log "cf-probe not found or not executable"

        return 1

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

    diagnose)
        diagnose
        ;;

    version)
        version
        ;;

    *)
        echo "Usage:"
        echo "$0 {start|stop|restart|status|logs|diagnose|version}"
        exit 2
        ;;

esac