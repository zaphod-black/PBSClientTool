#!/usr/bin/env python3
"""
Simple HTTP API server for PBS Client dashboard and monitoring
Unix philosophy: Simple, focused, does one thing well
"""

import os
import sys
import json
import logging
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime
from pathlib import Path

# Configuration
PORT = int(os.getenv('API_PORT', '8080'))
LOG_DIR = Path('/logs')
DASHBOARD_PATH = Path('/usr/local/share/dashboard.html')

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='[API] [%(asctime)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
log = logging.getLogger(__name__)


class PBSAPIHandler(BaseHTTPRequestHandler):
    """Handler for PBS Client API requests"""

    def log_message(self, format, *args):
        """Override to use our logging format"""
        log.info(f"{self.command} {self.path} - {format % args}")

    def send_json(self, data, status=200):
        """Send JSON response"""
        json_data = json.dumps(data, indent=2)
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', len(json_data))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Connection', 'close')
        self.end_headers()
        self.wfile.write(json_data.encode())

    def send_html(self, html_content, status=200):
        """Send HTML response"""
        self.send_response(status)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', len(html_content))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Connection', 'close')
        self.end_headers()
        self.wfile.write(html_content.encode())

    def send_text(self, text_content, status=200):
        """Send plain text response"""
        self.send_response(status)
        self.send_header('Content-Type', 'text/plain; charset=utf-8')
        self.send_header('Content-Length', len(text_content))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Connection', 'close')
        self.end_headers()
        self.wfile.write(text_content.encode())

    def do_GET(self):
        """Handle GET requests"""
        path = self.path.split('?')[0]  # Strip query params

        # Dashboard (root or /dashboard.html)
        if path in ('/', '/dashboard.html'):
            if DASHBOARD_PATH.exists():
                html = DASHBOARD_PATH.read_text()
                self.send_html(html)
            else:
                self.send_json({
                    'error': 'Dashboard not found',
                    'path': str(DASHBOARD_PATH)
                }, status=404)
            return

        # Status endpoint
        if path == '/status':
            status_file = LOG_DIR / 'status.json'
            if status_file.exists():
                try:
                    status_data = json.loads(status_file.read_text())
                    self.send_json(status_data)
                except json.JSONDecodeError as e:
                    self.send_json({
                        'error': 'Invalid status file',
                        'details': str(e)
                    }, status=500)
            else:
                # Default status if file doesn't exist yet
                self.send_json({
                    'status': 'idle',
                    'last_backup': 'never',
                    'last_result': 'unknown',
                    'next_scheduled': 'unknown',
                    'repository': os.getenv('PBS_REPOSITORY', 'not configured'),
                    'hostname': os.getenv('BACKUP_HOSTNAME', os.uname().nodename)
                })
            return

        # Health check
        if path == '/health':
            self.send_json({
                'status': 'healthy',
                'uptime': self._get_uptime(),
                'timestamp': datetime.now().isoformat()
            })
            return

        # Logs endpoint
        if path == '/logs':
            log_file = LOG_DIR / 'backup.log'
            if log_file.exists():
                # Return last 100 lines
                lines = log_file.read_text().splitlines()
                recent_lines = lines[-100:] if len(lines) > 100 else lines
                self.send_text('\n'.join(recent_lines))
            else:
                self.send_text('No logs available yet')
            return

        # Not found - show available endpoints
        self.send_json({
            'error': 'Not found',
            'path': path,
            'available_endpoints': [
                '/ - Dashboard web UI',
                '/status - Current backup status (JSON)',
                '/health - Health check (JSON)',
                '/logs - Recent backup logs (text)',
                '/backup - Trigger backup (POST)'
            ]
        }, status=404)

    def do_POST(self):
        """Handle POST requests"""
        path = self.path.split('?')[0]

        # Trigger backup
        if path == '/backup':
            # Read request body if present
            content_length = int(self.headers.get('Content-Length', 0))
            if content_length > 0:
                body = self.rfile.read(content_length)
                try:
                    params = json.loads(body)
                except json.JSONDecodeError:
                    params = {}
            else:
                params = {}

            # Trigger backup script
            backup_script = '/usr/local/bin/backup'
            if Path(backup_script).exists():
                log.info('Triggering backup via API...')
                os.system(f'{backup_script} > /logs/backup.log 2>&1 &')
                self.send_json({
                    'status': 'triggered',
                    'message': 'Backup started in background',
                    'timestamp': datetime.now().isoformat()
                })
            else:
                self.send_json({
                    'error': 'Backup script not found',
                    'path': backup_script
                }, status=500)
            return

        # Not found
        self.send_json({
            'error': 'Not found',
            'path': path,
            'available_endpoints': [
                '/backup - Trigger backup (POST)'
            ]
        }, status=404)

    def _get_uptime(self):
        """Get container uptime"""
        try:
            with open('/proc/uptime', 'r') as f:
                uptime_seconds = float(f.read().split()[0])
                hours = int(uptime_seconds // 3600)
                minutes = int((uptime_seconds % 3600) // 60)
                return f'{hours}h {minutes}m'
        except:
            return 'unknown'


def main():
    """Start the HTTP server"""
    server_address = ('', PORT)
    httpd = HTTPServer(server_address, PBSAPIHandler)

    log.info(f'Starting API server on port {PORT}')
    log.info(f'Dashboard: http://localhost:{PORT}/')
    log.info(f'API endpoints: /status /health /logs /backup')

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        log.info('Shutting down API server')
        httpd.shutdown()
        return 0
    except Exception as e:
        log.error(f'Server error: {e}')
        return 1


if __name__ == '__main__':
    sys.exit(main())
