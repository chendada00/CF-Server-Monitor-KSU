#!/system/bin/sh

MODDIR="${0%/*}"
MODDIR="${MODDIR%/*}"

DATA_DIR="/data/adb/cf-server-monitor"

BIN="$MODDIR/bin/cf-probe"
DEFAULT_CONFIG="$MODDIR/config/config.conf"
CONFIG="$DATA_DIR/config.conf"

PIDFILE="$DATA_DIR/cf-probe.pid"
LOGFILE="$DATA_DIR/cf-probe.log"

mkdir -p "$DATA_DIR"

init_config() {
    if [ ! -f "$CONFIG" ]; then
        echo "Initializing config..."
        cp "$DEFAULT_CONFIG" "$CONFIG" || return 1
        chmod 600 "$CONFIG"
    fi
}

pid_alive() {
    [ -n "$1" ] && kill -0 "$1" 2>/dev/null
}

get_pid() {
    [ -f "$PIDFILE" ] || return 1

    PID="$(cat "$PIDFILE" 2>/dev/null)"

    case "$PID" in
        ''|*[!0-9]*)
            return 1
            ;;
    esac

    pid_alive "$PID" || return 1

    echo "$PID"
}

start() {
    init_config || {
        echo "ERROR: failed to initialize config"
        return 1
    }

    if PID="$(get_pid)"; then
        echo "Already running. PID=$PID"
        return 0
    fi

    rm -f "$PIDFILE"

    if [ ! -f "$BIN" ]; then
        echo "ERROR: cf-probe not found:"
        echo "$BIN"
        return 1
    fi

    if [ ! -x "$BIN" ]; then
        echo "ERROR: cf-probe is not executable:"
        echo "$BIN"
        return 1
    fi

    echo "Starting CF Server Monitor..."

    # 官方 Agent 正确的运行方式：
    #
    # cf-probe run -config=/path/config.conf
    #
    # 不要在这里传 -id -secret -url，
    # 这些参数属于 cf-probe install。

    DEBUG="0"

    if [ -f "$CONFIG" ]; then
        DEBUG="$(sed -n 's/^DEBUG="\{0,1\}\([^"]*\).*/\1/p' "$CONFIG" | head -n 1)"

        [ -n "$DEBUG" ] || DEBUG="0"
    fi


    if [ "$DEBUG" = "1" ]; then

        nohup "$BIN" run \
            -config="$CONFIG" \
            -debug=1 \
            >> "$LOGFILE" 2>&1 < /dev/null &

    else

        nohup "$BIN" run \
            -config="$CONFIG" \
            >> "$LOGFILE" 2>&1 < /dev/null &

    fi

    PID=$!

    sleep 2

    if pid_alive "$PID"; then
        echo "$PID" > "$PIDFILE"
        echo "Started successfully."
        echo "PID=$PID"
        return 0
    fi

    echo "ERROR: cf-probe failed to start"
    echo
    echo "Last log:"
    tail -n 30 "$LOGFILE" 2>/dev/null

    rm -f "$PIDFILE"

    return 1
}

stop() {
    PID="$(get_pid)"

    if [ -z "$PID" ]; then
        rm -f "$PIDFILE"
        echo "Already stopped."
        return 0
    fi

    echo "Stopping CF Server Monitor..."
    echo "PID=$PID"

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
        echo "Graceful stop timed out."
        echo "Force killing..."

        kill -9 "$PID" 2>/dev/null || true
        sleep 1
    fi

    if pid_alive "$PID"; then
        echo "ERROR: failed to stop process"
        return 1
    fi

    rm -f "$PIDFILE"

    echo "Stopped."
}

restart() {
    echo "Restarting..."

    stop || return 1

    sleep 1

    start
}

status() {
    init_config >/dev/null 2>&1

    if PID="$(get_pid)"; then
        echo "STATUS=RUNNING"
        echo "PID=$PID"
    else
        echo "STATUS=STOPPED"
    fi

    echo
    echo "CONFIG=$CONFIG"
    echo "LOG=$LOGFILE"

    if [ -f "$CONFIG" ]; then
        echo
        echo "Configuration:"
        grep -v '^SECRET=' "$CONFIG" 2>/dev/null
    fi
}

logs() {
    if [ -f "$LOGFILE" ]; then
        tail -n 100 "$LOGFILE"
    else
        echo "No logs yet."
    fi
}

version() {
    if [ -x "$BIN" ]; then
        "$BIN" version
    else
        echo "cf-probe not found or not executable"
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

    version)
        version
        ;;

    *)
        echo "Usage:"
        echo "$0 {start|stop|restart|status|logs|version}"
        exit 2
        ;;
esac