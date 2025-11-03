#!/bin/bash
# Simple API server for PBS Client container management
# Provides REST endpoints for status, manual backup, etc.
#
# Now uses Python's http.server for proper HTTP handling
# (netcat had bidirectional pipe issues preventing request parsing)

exec /usr/local/bin/api-server.py
