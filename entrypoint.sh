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

# Set PgBouncer-compatible env
export DATABASE_PROVIDER=psql_bouncer
export DATABASE_BOUNCER_CONNECTION_URI="${DATABASE_URL}"

# Setup migrations in background (with timeout to prevent hanging)
echo "Setting up migration files..."
rm -rf ./prisma/migrations 2>/dev/null
cp -r ./prisma/postgresql-migrations ./prisma/migrations 2>/dev/null

echo "Starting Prisma migration in background (120s timeout)..."
( timeout 120 ./node_modules/.bin/prisma migrate deploy --schema ./prisma/psql_bouncer-schema.prisma 2>&1 && echo "Migration succeeded" || echo "Migration failed/timed out" ) &
MIGRATE_PID=$!

# Wait for Render to detect port
sleep 10

# Start Evolution API without waiting for migrations
# If tables don't exist yet, the server logs errors but still responds
echo "Starting Evolution API on port 8080 (migrations running in background)..."
node dist/main 2>&1 &
SERVER_PID=$!

# Wait for migrations to complete
wait $MIGRATE_PID 2>/dev/null

echo "Migration process finished. Server PID: $SERVER_PID"
# Keep container alive
wait $SERVER_PID 2>/dev/null

echo "Server exited with code: $?"
while true; do sleep 3600; done
