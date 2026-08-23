#!/system/bin/sh
# Reads base64 encoded key=value lines from stdin and atomically writes config.conf.
# Allowed keys are fixed; values are encoded as shell-safe double-quoted strings.

MODDIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CONFIG="$MODDIR/config/config.conf"
TMP="$CONFIG.tmp.$$"

input=$(cat)
decoded=$(printf '%s' "$input" | base64 -d 2>/dev/null) || {
    echo "ERROR: invalid base64 payload"
    exit 1
}

ID=""
SECRET=""
URL=""
INTERVAL=""
COLLECT_INTERVAL=""
CONNECTION_MODE=""

while IFS='=' read -r key value; do
    case "$key" in
        ID) ID=$value ;;
        SECRET) SECRET=$value ;;
        URL) URL=$value ;;
        INTERVAL) INTERVAL=$value ;;
        COLLECT_INTERVAL) COLLECT_INTERVAL=$value ;;
        CONNECTION_MODE) CONNECTION_MODE=$value ;;
    esac
done <<EOF
$decoded
EOF

[ -n "$ID" ] || { echo "ERROR: ID is required"; exit 1; }
[ -n "$SECRET" ] || { echo "ERROR: SECRET is required"; exit 1; }
[ -n "$URL" ] || { echo "ERROR: URL is required"; exit 1; }

case "$INTERVAL" in
    ''|*[!0-9]*) echo "ERROR: INTERVAL must be a non-negative integer"; exit 1 ;;
esac

case "$COLLECT_INTERVAL" in
    ''|*[!0-9]*) echo "ERROR: COLLECT_INTERVAL must be a non-negative integer"; exit 1 ;;
esac

case "$CONNECTION_MODE" in
    http|https) ;;
    *) echo "ERROR: CONNECTION_MODE must be http or https"; exit 1 ;;
esac

escape_dq() {
    # Escape characters that are special inside shell double quotes.
    printf '%s' "$1" | sed 's/[\\$`"]/\\&/g'
}

{
    echo "# CF Server Monitor configuration"
    printf 'ID="%s"\n' "$(escape_dq "$ID")"
    printf 'SECRET="%s"\n' "$(escape_dq "$SECRET")"
    printf 'URL="%s"\n' "$(escape_dq "$URL")"
    printf 'INTERVAL="%s"\n' "$INTERVAL"
    printf 'COLLECT_INTERVAL="%s"\n' "$COLLECT_INTERVAL"
    printf 'CONNECTION_MODE="%s"\n' "$CONNECTION_MODE"
} > "$TMP" || exit 1

mv "$TMP" "$CONFIG" || {
    rm -f "$TMP"
    echo "ERROR: failed to replace config"
    exit 1
}

echo "OK"
