#!/bin/bash
# Simple API server for PBS Client container management
# Provides REST endpoints for status, manual backup, etc.

PORT=${API_PORT:-8080}

log() {
    echo "[API] [$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Simple HTTP server using nc
log "Starting API server on port $PORT"

while true; do
    (
        read -r method path protocol

        # Strip carriage returns and whitespace from path
        path=$(echo "$path" | tr -d '\r' | xargs)

        # Debug logging
        log "REQUEST: method=[$method] path=[$path] len=${#path}"

        # Read headers (discard)
        while read -r line; do
            [ -z "$line" ] || [ "$line" = $'\r' ] && break
        done

        # Handle request directly (avoid subshell variable issues)
        case "$path" in
            /|/dashboard.html)
                MIME_TYPE="text/html"
                BODY=$(cat /usr/local/share/dashboard.html)
                ;;
            /status)
                MIME_TYPE="application/json"
                if [ -f /logs/status.json ]; then
                    BODY=$(cat /logs/status.json)
                else
                    BODY='{"error":"No backup status available"}'
                fi
                ;;
            /health)
                MIME_TYPE="application/json"
                if /usr/local/bin/healthcheck >/dev/null 2>&1; then
                    BODY='{"status":"healthy"}'
                else
                    BODY='{"status":"unhealthy"}'
                fi
                ;;
            /backup)
                MIME_TYPE="application/json"
                if [ "$method" = "POST" ]; then
                    BODY='{"status":"starting","message":"Backup triggered"}'
                    /usr/local/bin/pbs-backup &
                else
                    BODY='{"error":"Use POST method to trigger backup"}'
                fi
                ;;
            /logs)
                MIME_TYPE="application/json"
                if [ -f /logs/last-backup.log ]; then
                    BODY=$(tail -n 50 /logs/last-backup.log | jq -R -s -c 'split("\n") | {logs: .}')
                else
                    BODY='{"logs":[]}'
                fi
                ;;
            *)
                MIME_TYPE="application/json"
                BODY='{"error":"Not found","available_endpoints":["/","/status","/health","/backup","/logs"]}'
                ;;
        esac

        CONTENT_LENGTH=${#BODY}

        # Send HTTP response
        cat << EOF
HTTP/1.1 200 OK
Content-Type: $MIME_TYPE
Content-Length: $CONTENT_LENGTH
Access-Control-Allow-Origin: *
Connection: close

$BODY
EOF
    ) | nc -l -p $PORT -q 1
done
