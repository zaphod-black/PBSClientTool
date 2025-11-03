#!/bin/bash
# Simple API server for PBS Client container management
# Provides REST endpoints for status, manual backup, etc.

PORT=${API_PORT:-8080}

log() {
    echo "[API] [$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to handle HTTP requests
handle_request() {
    local method="$1"
    local path="$2"
    
    case "$path" in
        /status)
            if [ -f /logs/status.json ]; then
                cat /logs/status.json
            else
                echo '{"error":"No backup status available"}'
            fi
            ;;
        /health)
            if /usr/local/bin/healthcheck >/dev/null 2>&1; then
                echo '{"status":"healthy"}'
            else
                echo '{"status":"unhealthy"}'
            fi
            ;;
        /backup)
            if [ "$method" = "POST" ]; then
                echo '{"status":"starting","message":"Backup triggered"}'
                /usr/local/bin/pbs-backup &
            else
                echo '{"error":"Use POST method to trigger backup"}'
            fi
            ;;
        /logs)
            if [ -f /logs/last-backup.log ]; then
                tail -n 50 /logs/last-backup.log | jq -R -s -c 'split("\n")'
            else
                echo '{"logs":[]}'
            fi
            ;;
        *)
            echo '{"error":"Not found","available_endpoints":["/status","/health","/backup","/logs"]}'
            ;;
    esac
}

# Simple HTTP server using nc
log "Starting API server on port $PORT"

while true; do
    {
        read -r method path protocol
        
        # Read headers (discard)
        while read -r line; do
            [ -z "$line" ] || [ "$line" = $'\r' ] && break
        done
        
        # Generate response
        RESPONSE=$(handle_request "$method" "$path")
        CONTENT_LENGTH=${#RESPONSE}
        
        # Send HTTP response
        cat << EOF
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: $CONTENT_LENGTH
Access-Control-Allow-Origin: *
Connection: close

$RESPONSE
EOF
    } | nc -l -p $PORT -q 1
done
