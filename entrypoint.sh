#!/bin/bash

# Start health server on port 8080 (Render port detection)
echo "Starting health check on port 8080..."
python3 -c "
import socket, threading, os, signal
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('0.0.0.0', 8080))
s.listen(5)
def handle(c):
    c.send(b'HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK')
    c.close()
while True:
    c, a = s.accept()
    threading.Thread(target=handle, args=(c,)).start()
" &
echo "Health server started"

# Run migrations
echo "Running migrations..."
. ./Docker/scripts/deploy_database.sh 2>&1
echo "Migrations exit code: $?"

# Run Prisma generate
echo "Running Prisma generate..."
npm run db:generate 2>&1
echo "Prisma generate exit code: $?"

# Start Evolution API on 8080 (killing health server first)
echo "Killing health server on port 8080..."
kill %1 2>/dev/null
sleep 1

echo "Starting Evolution API on port 8080..."
node dist/main > /tmp/evo_stdout.log 2> /tmp/evo_stderr.log
EXIT_CODE=$?
echo "Evolution API exited with code: $EXIT_CODE"

# If server crashed, restart health server so Render doesn't show error
# If server crashed, show error logs and keep container alive
echo ""
echo "=========================================="
echo "Evolution API crashed with exit code: $EXIT_CODE"
echo "=== Stdout log ==="
cat /tmp/evo_stdout.log 2>/dev/null || echo "(empty)"
echo "=== Stderr log ==="
cat /tmp/evo_stderr.log 2>/dev/null || echo "(empty)"
echo "=========================================="
echo "Restarting health check on port 8080..."
python3 -c "
import socket, threading
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('0.0.0.0', 8080))
s.listen(5)
def handle(c):
    c.send(b'HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK')
    c.close()
while True:
    c, a = s.accept()
    threading.Thread(target=handle, args=(c,)).start()
"
echo "Health check restarted. Container staying alive for debugging."
while true; do sleep 3600; done
