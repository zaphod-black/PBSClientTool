# Proxmox Backup Client - Docker Container
# Cross-platform PBS client for Windows, Mac, and Linux

FROM debian:bookworm-slim

# Metadata
LABEL maintainer="PBSClientTool"
LABEL description="Cross-platform Proxmox Backup Client with scheduler"
LABEL version="1.0.0"

# Install dependencies
RUN apt-get update && \
    apt-get install -y \
    wget \
    gnupg \
    cron \
    curl \
    jq \
    python3 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Add Proxmox repository and install PBS client
RUN wget -q https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg \
         -O /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg && \
    echo "deb [arch=amd64] http://download.proxmox.com/debian/pbs-client bookworm main" \
         > /etc/apt/sources.list.d/pbs-client.list && \
    apt-get update && \
    apt-get install -y proxmox-backup-client && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create directories
RUN mkdir -p /config /backup-scripts /host-data /logs

# Copy scripts
COPY scripts/entrypoint.sh /usr/local/bin/
COPY scripts/backup.sh /usr/local/bin/pbs-backup
COPY scripts/healthcheck.sh /usr/local/bin/healthcheck
COPY scripts/api-server.sh /usr/local/bin/api-server
COPY scripts/api-server.py /usr/local/bin/api-server.py
COPY scripts/dashboard.html /usr/local/share/dashboard.html

RUN chmod +x /usr/local/bin/entrypoint.sh \
             /usr/local/bin/pbs-backup \
             /usr/local/bin/healthcheck \
             /usr/local/bin/api-server \
             /usr/local/bin/api-server.py

# Expose API port (optional)
EXPOSE 8080

# Health check
HEALTHCHECK --interval=5m --timeout=10s --start-period=30s --retries=3 \
    CMD /usr/local/bin/healthcheck

# Default environment variables
ENV MODE=daemon \
    BACKUP_SCHEDULE="0 2 * * *" \
    BACKUP_PATHS="/host-data" \
    EXCLUDE_PATTERNS="/host-data/tmp /host-data/var/tmp /host-data/proc /host-data/sys /host-data/dev" \
    TIMEZONE=UTC

VOLUME ["/config", "/logs", "/host-data"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["daemon"]
