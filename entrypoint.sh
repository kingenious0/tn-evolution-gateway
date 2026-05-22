#!/bin/bash

# Start dummy health server on port 8080 for Render's port scanner
echo "Starting dummy health server on port 8080..."
python3 -c "
import socket, threading, time, sys
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('0.0.0.0', 8080))
s.listen(5)
def handle(c):
    c.send(b'HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK')
    c.close()
s.settimeout(20)
try:
    for _ in range(100):
        try:
            c, a = s.accept()
            threading.Thread(target=handle, args=(c,)).start()
        except socket.timeout:
            break
except:
    pass
" &
DUMMY_PID=$!
echo "Dummy health server started (PID: $DUMMY_PID)"

# Run database migrations
echo "Running database migrations..."
. ./Docker/scripts/deploy_database.sh
MIGRATE_EXIT=$?
echo "Migrations exit code: $MIGRATE_EXIT"

# Wait for Render to detect the port
echo "Waiting for Render port scan to detect port 8080..."
sleep 15

# Kill the dummy server to free port 8080 for Evolution API
echo "Stopping dummy health server..."
kill $DUMMY_PID 2>/dev/null
wait $DUMMY_PID 2>/dev/null
sleep 2

# Start real Evolution API
echo "Starting Evolution API on port 8080..."
npm run start:prod
