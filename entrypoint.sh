#!/bin/bash

# Start proxy server on port 8080 that forwards to Evolution API on 8081
echo "Starting proxy server on port 8080 -> 8081..."
python3 -c "
import socket, threading, select, sys

def forward(src, dst):
    try:
        while True:
            r, _, _ = select.select([src, dst], [], [])
            if src in r:
                data = src.recv(4096)
                if not data:
                    break
                dst.sendall(data)
            if dst in r:
                data = dst.recv(4096)
                if not data:
                    break
                src.sendall(data)
    except:
        pass
    finally:
        try: src.close()
        except: pass
        try: dst.close()
        except: pass

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('0.0.0.0', 8080))
s.listen(50)

while True:
    c, a = s.accept()
    try:
        backend = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        backend.connect(('127.0.0.1', 8081))
        threading.Thread(target=forward, args=(c, backend)).start()
        threading.Thread(target=forward, args=(backend, c)).start()
    except:
        # If backend not ready, return 502
        c.send(b'HTTP/1.1 502 Bad Gateway\r\nContent-Length: 12\r\n\r\nNot Ready Yet')
        c.close()
" &
PROXY_PID=$!
echo "Proxy started (PID: $PROXY_PID)"

# Set Evolution API to listen on port 8081
export SERVER_PORT=8081
export PORT=8081

# Run database migrations
echo "Running database migrations..."
. ./Docker/scripts/deploy_database.sh
echo "Migrations complete."

# Start Evolution API on port 8081 (proxied via 8080)
echo "Starting Evolution API on port 8081..."
npm run start:prod
