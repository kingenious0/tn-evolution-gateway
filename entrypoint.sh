#!/bin/bash

# Start health check server on port 8080 for Render detection
echo "Starting health check on port 8080..."
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
" &
echo "Health server started. Waiting for Render to detect port..."
sleep 10

# Kill health server, free port 8080
echo "Starting Evolution API..."
kill %1 2>/dev/null
sleep 1

# Start Evolution API directly (migrations already applied)
node dist/main 2>&1
EXIT_CODE=$?

echo "=========================================="
echo "Evolution API exited with code: $EXIT_CODE"
echo "=========================================="
