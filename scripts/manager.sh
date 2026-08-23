#!/system/bin/sh

MODDIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BIN="$MODDIR/bin/cf-probe"
CONFIG="$MODDIR/config/config.conf"
PIDFILE="$MODDIR/cf-probe.pid"
LOGDIR="$MODDIR/logs"
LOGFILE="$LOGDIR/cf-probe.log"

mkdir -p "$LOGDIR"

log() {
    printf '%s\n' "$*"
}

load_config() {
    [ -f "$CONFIG" ] || {
        log "ERROR: config file not found"
        return 1
    }

    # shellcheck disable=SC1090
    . "$CONFIG"

    [ -n "${ID:-}" ] || { log "ERROR: ID is empty"; return 1; }
    [ -n "${SECRET:-}" ] || { log "ERROR: SECRET is empty"; return 1; }
    [ -n "${URL:-}" ] || { log "ERROR: URL is empty"; return 1; }

    INTERVAL="${INTERVAL:-60}"
    COLLECT_INTERVAL="${COLLECT_INTERVAL:-0}"
    CONNECTION_MODE="${CONNECTION_MODE:-http}"
}

pid_alive() {
    [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null
}

get_pid() {
    [ -f "$PIDFILE" ] || return 1
    pid=$(cat "$PIDFILE" 2>/dev/null)
    case "$pid" in
        ''|*[!0-9]*) return 1 ;;
    esac
    pid_alive "$pid" || return 1
    printf '%s\n' "$pid"
}

is_running() {
    get_pid >/dev/null 2>&1
}

start() {
    if pid=$(get_pid); then
        log "Already running. PID=$pid"
        return 0
    fi

    rm -f "$PIDFILE"

    [ -x "$BIN" ] || {
        log "ERROR: cf-probe is missing or not executable: $BIN"
        return 1
    }

    load_config || return 1

    log "Starting cf-probe..."

    nohup "$BIN" \
        -id="$ID" \
        -secret="$SECRET" \
        -url="$URL" \
        -collect_interval="$COLLECT_INTERVAL" \
        -interval="$INTERVAL" \
        -connection_mode="$CONNECTION_MODE" \
        >> "$LOGFILE" 2>&1 &

    pid=$!

    sleep 1

    if pid_alive "$pid"; then
        printf '%s\n' "$pid" > "$PIDFILE"
        log "Started successfully. PID=$pid"
        return 0
    fi

    log "ERROR: process exited during startup"
    return 1
}

stop() {
    if ! pid=$(get_pid); then
        rm -f "$PIDFILE"
        log "Already stopped."
        return 0
    fi

    log "Stopping cf-probe. PID=$pid"
    kill "$pid" 2>/dev/null || true

    i=0
    while pid_alive "$pid"; do
        i=$((i + 1))
        [ "$i" -ge 10 ] && break
        sleep 1
    done

    if pid_alive "$pid"; then
        log "Graceful stop timed out, sending SIGKILL."
        kill -9 "$pid" 2>/dev/null || true
        sleep 1
    fi

    rm -f "$PIDFILE"

    if pid_alive "$pid"; then
        log "ERROR: failed to stop process"
        return 1
    fi

    log "Stopped."
}

restart() {
    stop || return 1
    sleep 1
    start
}

status() {
    if pid=$(get_pid); then
        log "RUNNING"
        log "PID=$pid"
    else
        log "STOPPED"
    fi

    if [ -f "$CONFIG" ]; then
        . "$CONFIG"
        log "ID=${ID:-}"
        log "URL=${URL:-}"
        log "INTERVAL=${INTERVAL:-}"
        log "COLLECT_INTERVAL=${COLLECT_INTERVAL:-}"
        log "CONNECTION_MODE=${CONNECTION_MODE:-}"
    fi
}

logs() {
    if [ -f "$LOGFILE" ]; then
        tail -n 100 "$LOGFILE"
    else
        log "No logs yet."
    fi
}

case "${1:-}" in
    start) start ;;
    stop) stop ;;
    restart) restart ;;
    status) status ;;
    logs) logs ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs}"
        exit 2
        ;;
esac
