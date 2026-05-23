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

# Set environment for PgBouncer-compatible Prisma
export DATABASE_PROVIDER=psql_bouncer

# Copy migration files (psql_bouncer uses the same migrations as postgresql)
echo "Setting up Prisma migrations..."
rm -rf ./prisma/migrations 2>/dev/null
cp -r ./prisma/postgresql-migrations ./prisma/migrations 2>/dev/null

# Run migrations with psql_bouncer schema (PgBouncer compatible)
echo "Running Prisma migrate deploy with psql_bouncer schema..."
./node_modules/.bin/prisma migrate deploy --schema ./prisma/psql_bouncer-schema.prisma 2>&1
MIGRATE_EXIT=$?
echo "Migration exit code: $MIGRATE_EXIT"

echo "Running Prisma generate with psql_bouncer schema..."
./node_modules/.bin/prisma generate --schema ./prisma/psql_bouncer-schema.prisma 2>&1
GENERATE_EXIT=$?
echo "Generate exit code: $GENERATE_EXIT"

# Kill health server to free port 8080
echo "Killing health server..."
kill %1 2>/dev/null
sleep 1

# Start Evolution API with psql_bouncer provider
export DATABASE_PROVIDER=psql_bouncer
echo "Starting Evolution API on port 8080..."
node dist/main 2>&1
EXIT_CODE=$?

echo "Evolution API exited with code: $EXIT_CODE"
while true; do sleep 3600; done
