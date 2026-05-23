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

# Give Render time to detect port 8080
sleep 8

# Kill health server to free port 8080
echo "Killing health server..."
kill %1 2>/dev/null
sleep 1

# Add pgbouncer=true so Prisma doesn't use prepared statements through pooler
export DATABASE_CONNECTION_URI="${DATABASE_CONNECTION_URI}?pgbouncer=true"
echo "DB URI (pgbouncer mode): $(echo $DATABASE_CONNECTION_URI | sed 's/:W[^@]*@/:****@/')"

# Copy migration files
echo "Setting up Prisma migrations..."
rm -rf ./prisma/migrations 2>/dev/null
cp -r ./prisma/postgresql-migrations ./prisma/migrations 2>/dev/null

# Run migration SQL through pooler using Node.js script
# (prisma migrate deploy uses prepared statements which PgBouncer blocks)
echo "Running migrations via pooler..."
node /evolution/migrate-via-pooler.mjs 2>&1
MIGRATE_EXIT=$?
echo "Migration exit code: $MIGRATE_EXIT"

if [ $MIGRATE_EXIT -ne 0 ]; then
  echo "Migration failed, but continuing to generate and start..."
fi

echo "Running Prisma generate..."
./node_modules/.bin/prisma generate --schema ./prisma/postgresql-schema.prisma 2>&1
GENERATE_EXIT=$?
echo "Generate exit code: $GENERATE_EXIT"

echo "Starting Evolution API on port 8080..."
node dist/main 2>&1
EXIT_CODE=$?

echo "Evolution API exited with code: $EXIT_CODE"
while true; do sleep 3600; done
