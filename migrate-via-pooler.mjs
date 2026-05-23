import { readdirSync, readFileSync, existsSync } from 'fs';
import { join, resolve } from 'path';
import { createRequire } from 'module';

const require = createRequire(import.meta.url);
const { PrismaClient } = require('@prisma/client');

const MIGRATIONS_DIR = resolve('./prisma/migrations');

function escapeSql(val) {
  if (val === null || val === undefined) return 'NULL';
  return "'" + val.replace(/'/g, "''") + "'";
}

async function ensurePrismaMigrationsTable(prisma) {
  try {
    await prisma.$queryRawUnsafe('SELECT 1 FROM "_prisma_migrations" LIMIT 1');
  } catch {
    console.log('Creating _prisma_migrations table...');
    await prisma.$executeRawUnsafe(`
      CREATE TABLE "_prisma_migrations" (
        "id" TEXT PRIMARY KEY,
        "checksum" TEXT NOT NULL,
        "finished_at" TIMESTAMPTZ,
        "migration_name" TEXT NOT NULL,
        "logs" TEXT,
        "rolled_back_at" TIMESTAMPTZ,
        "started_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        "applied_steps_count" INTEGER NOT NULL DEFAULT 1
      );
    `);
  }
}

async function isMigrationApplied(prisma, migrationId) {
  try {
    const result = await prisma.$queryRawUnsafe(
      `SELECT 1 as ok FROM "_prisma_migrations" WHERE "migration_name" = ${escapeSql(migrationId)} LIMIT 1`
    );
    return result && result.length > 0;
  } catch {
    return false;
  }
}

async function runMigrations() {
  if (!existsSync(MIGRATIONS_DIR)) {
    console.log('No migrations directory found, skipping.');
    return;
  }

  const dirs = readdirSync(MIGRATIONS_DIR, { withFileTypes: true })
    .filter(d => d.isDirectory())
    .map(d => d.name)
    .sort();

  if (dirs.length === 0) {
    console.log('No migration directories found, skipping.');
    return;
  }

  console.log(`Found ${dirs.length} migrations`);
  const prisma = new PrismaClient();
  await prisma.$connect();
  console.log('Connected to database');

  await ensurePrismaMigrationsTable(prisma);

  for (const dir of dirs) {
    const sqlPath = join(MIGRATIONS_DIR, dir, 'migration.sql');
    if (!existsSync(sqlPath)) {
      console.log(`Skipping ${dir}: no migration.sql`);
      continue;
    }

    if (await isMigrationApplied(prisma, dir)) {
      console.log(`Skipping ${dir}: already applied`);
      continue;
    }

    console.log(`Applying: ${dir}`);
    const sql = readFileSync(sqlPath, 'utf-8');

    const rawStatements = sql.split(/;\s*\r?\n/);
    const statements = rawStatements
      .map(s => s.trim().replace(/\r$/, ''))
      .filter(s => s.length > 0 && !s.startsWith('--'));

    const errors = [];
    for (const stmt of statements) {
      try {
        await prisma.$executeRawUnsafe(stmt + ';');
      } catch (err) {
        const msg = err.message || '';
        // DROP on missing table/type/column is harmless on fresh DB
        if (
          msg.includes('does not exist') &&
          (stmt.toUpperCase().includes('DROP TABLE') ||
           stmt.toUpperCase().includes('DROP TYPE') ||
           stmt.toUpperCase().includes('DROP COLUMN') ||
           stmt.toUpperCase().includes('ALTER TABLE') ||
           stmt.toUpperCase().includes('ALTER TYPE'))
        ) {
          console.log(`  Warn: ${msg.split('\n')[0]}`);
          errors.push(msg);
        } else {
          console.error(`  Error: ${msg}`);
          errors.push(msg);
        }
      }
    }

    const checksum = Buffer.from(sql.replace(/\s+/g, ' ')).subarray(0, 32).toString('hex');
    const logs = errors.length > 0 ? errors.join('\n') : null;
    const migrationId = escapeSql(dir);
    const escapedChecksum = escapeSql(checksum);
    const escapedName = escapeSql(dir);
    const escapedLogs = logs ? escapeSql(logs) : 'NULL';

    await prisma.$executeRawUnsafe(
      `INSERT INTO "_prisma_migrations" ("id", "checksum", "finished_at", "migration_name", "logs", "rolled_back_at", "started_at", "applied_steps_count")
       VALUES (${migrationId}, ${escapedChecksum}, NOW(), ${escapedName}, ${escapedLogs}, NULL, NOW(), 1)`
    );

    console.log(`  OK`);
  }

  console.log('All migrations processed');
  await prisma.$disconnect();
}

runMigrations()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('Fatal:', err.message);
    process.exit(1);
  });
