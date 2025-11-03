#!/bin/bash
# Quick test of the dashboard

echo "Starting test container with API enabled..."
docker run -d --name pbs-dashboard-test \
  -p 8080:8080 \
  -e MODE=daemon \
  -e ENABLE_API=true \
  -e PBS_REPOSITORY="test@pam@localhost:8007:test" \
  -e PBS_PASSWORD="test" \
  pbsclient:latest

echo "Waiting for container to start..."
sleep 3

echo ""
echo "Testing dashboard endpoints:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "1. Testing HTML dashboard (/)..."
curl -s -I http://localhost:8080/ | grep -E "HTTP|Content-Type"
echo ""

echo "2. Testing health endpoint..."
curl -s http://localhost:8080/health | jq
echo ""

echo "3. Testing status endpoint..."
curl -s http://localhost:8080/status | jq
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "✓ Dashboard is running!"
echo "  Open in browser: http://localhost:8080"
echo ""
echo "To stop test container:"
echo "  docker stop pbs-dashboard-test && docker rm pbs-dashboard-test"
