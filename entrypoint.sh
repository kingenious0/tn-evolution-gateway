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
echo "Health server started"

# Give Render time to detect port
sleep 8

# Copy migration files  
echo "Setting up Prisma migrations..."
rm -rf ./prisma/migrations 2>/dev/null
cp -r ./prisma/postgresql-migrations ./prisma/migrations 2>/dev/null

# Run migrations with timeout (15 seconds to avoid hanging)
echo "Running Prisma migrate deploy (timeout: 15s)..."
timeout 15 ./node_modules/.bin/prisma migrate deploy --schema ./prisma/postgresql-schema.prisma 2>&1
MIGRATE_EXIT=$?
echo "Migration exit code: $MIGRATE_EXIT"

# Run Prisma generate with timeout
echo "Running Prisma generate (timeout: 15s)..."
timeout 15 ./node_modules/.bin/prisma generate --schema ./prisma/postgresql-schema.prisma 2>&1
GENERATE_EXIT=$?
echo "Generate exit code: $GENERATE_EXIT"

# Kill health server
echo "Killing health server..."
kill %1 2>/dev/null
sleep 1

# Start Evolution API
echo "Starting Evolution API on port 8080..."
node dist/main 2>&1
EXIT_CODE=$?

echo "Evolution API exited with code: $EXIT_CODE"
while true; do sleep 3600; done
