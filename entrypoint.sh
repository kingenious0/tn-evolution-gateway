#!/bin/bash
# Start a dummy HTTP server on port 8080 immediately
# so Render's port scanner detects an open port
echo "Starting dummy health server on port 8080..."
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
DUMMY_PID=$!

# Run the original Evolution API startup
echo "Starting Evolution API..."
. ./Docker/scripts/deploy_database.sh && npm run start:prod
