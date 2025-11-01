#!/bin/bash

# PBS Client Connection Test Script
# This script helps diagnose connection issues with Proxmox Backup Server

# Usage:
#   ./test-connection.sh <server> <port> <datastore> <username> <realm> <password>
#   or
#   ./test-connection.sh <server> <port> <datastore> <username> <realm> <token-name> <token-secret>

if [ $# -lt 6 ]; then
    echo "Usage:"
    echo "  Test with username/password:"
    echo "    $0 <server> <port> <datastore> <username> <realm> <password>"
    echo ""
    echo "  Test with API token:"
    echo "    $0 <server> <port> <datastore> <username> <realm> <token-name> <token-secret>"
    echo ""
    echo "Examples:"
    echo "  $0 192.168.1.181 8007 DEAD-BACKUP root pam mypassword"
    echo "  $0 192.168.1.181 8007 DEAD-BACKUP root pam backup-token a1b2c3d4-e5f6-7890"
    exit 1
fi

SERVER="$1"
PORT="$2"
DATASTORE="$3"
USERNAME="$4"
REALM="$5"

# Detect if this is password or token authentication
if [ $# -eq 6 ]; then
    # Username/Password
    PASSWORD="$6"
    REPO="${USERNAME}@${REALM}@${SERVER}:${PORT}:${DATASTORE}"
    AUTH_TYPE="password"
elif [ $# -eq 7 ]; then
    # API Token
    TOKEN_NAME="$6"
    TOKEN_SECRET="$7"
    REPO="${USERNAME}@${REALM}!${TOKEN_NAME}@${SERVER}:${PORT}:${DATASTORE}"
    PASSWORD="$TOKEN_SECRET"
    AUTH_TYPE="token"
else
    echo "Error: Invalid number of arguments"
    exit 1
fi

echo "=== PBS Client Connection Test ==="
echo "Authentication Type: $AUTH_TYPE"
echo "Repository: $REPO"
echo ""

export PBS_REPOSITORY="$REPO"
export PBS_PASSWORD="$PASSWORD"

# Test 1: Check if server is reachable
echo "Test 1: Server Reachability"
echo "----------------------------"
if timeout 5 curl -sk --max-time 5 "https://${SERVER}:${PORT}" >/dev/null 2>&1; then
    echo "✓ Server is reachable at https://${SERVER}:${PORT}"
else
    echo "✗ Server is NOT reachable"
    echo "  Check network connectivity and firewall settings"
    exit 1
fi
echo ""

# Test 2: Check for SSL fingerprint requirement
echo "Test 2: SSL Certificate Check"
echo "------------------------------"
echo "Attempting login to check for SSL fingerprint prompt..."
LOGIN_OUTPUT=$(timeout 10 proxmox-backup-client login 2>&1)
LOGIN_EXIT=$?

if echo "$LOGIN_OUTPUT" | grep -q "fingerprint:"; then
    echo "⚠ SSL certificate fingerprint confirmation required"
    FINGERPRINT=$(echo "$LOGIN_OUTPUT" | grep "fingerprint:" | head -1 | awk '{print $2}')
    echo "  Fingerprint: $FINGERPRINT"
    echo ""
    echo "To fix this, you need to accept the fingerprint. Options:"
    echo "  1. Run this command interactively once:"
    echo "     export PBS_REPOSITORY='$REPO'"
    echo "     export PBS_PASSWORD='***'"
    echo "     proxmox-backup-client login"
    echo ""
    echo "  2. Or use the --fingerprint flag in commands"
    echo ""
    echo "Would you like to accept this fingerprint now? (y/n)"
    read -r ACCEPT
    if [[ "$ACCEPT" == "y" || "$ACCEPT" == "Y" ]]; then
        echo "y" | proxmox-backup-client login
        if [ $? -eq 0 ]; then
            echo "✓ Fingerprint accepted and login successful"
        else
            echo "✗ Login failed even after accepting fingerprint"
            exit 1
        fi
    else
        echo "Fingerprint not accepted. Cannot continue tests."
        exit 1
    fi
elif [ $LOGIN_EXIT -eq 0 ]; then
    echo "✓ Login successful (no fingerprint prompt)"
else
    echo "✗ Login failed"
    echo "$LOGIN_OUTPUT"
    exit 1
fi
echo ""

# Test 3: List backup groups
echo "Test 3: Datastore Access"
echo "------------------------"
if proxmox-backup-client list 2>&1; then
    echo ""
    echo "✓ Successfully accessed datastore"
else
    echo "⚠ Could not list backup groups (this is normal if no backups exist)"
fi
echo ""

echo "=== All Tests Passed ==="
echo "Your PBS client is properly configured!"
