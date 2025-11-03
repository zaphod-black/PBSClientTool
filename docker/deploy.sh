#!/bin/bash
# Smart deployment script - detects platform and deploys appropriate config

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Detect platform
detect_platform() {
    case "$(uname -s)" in
        Linux*)
            echo "linux"
            ;;
        Darwin*)
            echo "macos"
            ;;
        CYGWIN*|MINGW*|MSYS*)
            echo "windows"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Check Docker is installed
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "ERROR: Docker is not installed"
        echo
        echo "Install Docker:"
        echo "  Linux: https://docs.docker.com/engine/install/"
        echo "  Windows: https://docs.docker.com/desktop/install/windows-install/"
        echo "  Mac: https://docs.docker.com/desktop/install/mac-install/"
        exit 1
    fi
    
    if ! docker ps &> /dev/null; then
        echo "ERROR: Docker is not running"
        echo "Start Docker and try again"
        exit 1
    fi
}

# Prompt for configuration
prompt_config() {
    echo
    echo "======================================"
    echo "  PBS Client Docker Setup"
    echo "======================================"
    echo
    
    read -p "PBS Server IP/hostname: " PBS_SERVER
    read -p "PBS Server port [8007]: " PBS_PORT
    PBS_PORT=${PBS_PORT:-8007}
    
    read -p "PBS Datastore name: " PBS_DATASTORE
    read -p "PBS Username: " PBS_USERNAME
    read -p "PBS Realm [pbs]: " PBS_REALM
    PBS_REALM=${PBS_REALM:-pbs}
    read -p "PBS Token name: " PBS_TOKEN
    read -sp "PBS Token secret: " PBS_PASSWORD
    echo
    
    PBS_REPOSITORY="${PBS_USERNAME}@${PBS_REALM}!${PBS_TOKEN}@${PBS_SERVER}:${PBS_PORT}:${PBS_DATASTORE}"
    
    read -p "Backup schedule (cron format) [0 2 * * *]: " SCHEDULE
    SCHEDULE=${SCHEDULE:-"0 2 * * *"}
    
    read -p "Container hostname [$(hostname)]: " CONTAINER_HOST
    CONTAINER_HOST=${CONTAINER_HOST:-$(hostname)}
}

# Create env file
create_env_file() {
    cat > .env << EOF
# PBS Configuration
PBS_REPOSITORY=${PBS_REPOSITORY}
PBS_PASSWORD=${PBS_PASSWORD}

# Backup Configuration
BACKUP_SCHEDULE=${SCHEDULE}
CONTAINER_HOSTNAME=${CONTAINER_HOST}

# Hostname
HOSTNAME=${CONTAINER_HOST}
COMPUTERNAME=${CONTAINER_HOST}
EOF
    
    chmod 600 .env
    log "Configuration saved to .env"
}

# Deploy
deploy() {
    local platform=$1
    local compose_file="docker-compose-${platform}.yml"
    
    if [ ! -f "$compose_file" ]; then
        echo "ERROR: $compose_file not found"
        exit 1
    fi
    
    log "Deploying PBS Client for $platform..."
    
    # Build if image doesn't exist
    if ! docker images pbsclient:latest | grep -q pbsclient; then
        warn "Image not found, building..."
        ./build.sh
    fi
    
    # Deploy
    docker-compose -f "$compose_file" up -d
    
    echo
    log "Deployment complete!"
    echo
    info "Container status:"
    docker-compose -f "$compose_file" ps
    echo
    info "View logs:"
    echo "  docker-compose -f $compose_file logs -f"
    echo
    info "Check backup status:"
    echo "  docker exec pbs-backup-client cat /logs/status.json"
    echo
    info "Manual backup:"
    echo "  docker exec pbs-backup-client /usr/local/bin/pbs-backup"
    echo
    warn "IMPORTANT: Backup your encryption key!"
    echo "  docker cp pbs-backup-client:/config/encryption-key.json ./encryption-key.json"
    echo
}

# Main
main() {
    echo
    echo "╔════════════════════════════════════════╗"
    echo "║  PBS Client Docker Deployment         ║"
    echo "╚════════════════════════════════════════╝"
    echo
    
    # Check prerequisites
    check_docker
    
    # Detect platform
    PLATFORM=$(detect_platform)
    info "Detected platform: $PLATFORM"
    
    if [ "$PLATFORM" = "unknown" ]; then
        echo "ERROR: Cannot detect platform"
        exit 1
    fi
    
    # Prompt for configuration
    prompt_config
    
    # Create env file
    create_env_file
    
    # Deploy
    deploy "$PLATFORM"
}

main "$@"
