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

  console.log(`Found ${dirs.length} migrations to apply`);
  const prisma = new PrismaClient();
  await prisma.$connect();
  console.log('Connected to database via pooler');

  try {
    for (const dir of dirs) {
      const sqlPath = join(MIGRATIONS_DIR, dir, 'migration.sql');
      if (!existsSync(sqlPath)) {
        console.log(`Skipping ${dir}: no migration.sql`);
        continue;
      }

      console.log(`Applying migration: ${dir}`);
      const sql = readFileSync(sqlPath, 'utf-8');

      const statements = sql
        .split(/;\s*\r?\n/)
        .map(s => s.trim().replace(/\r$/, ''))
        .filter(s => s.length > 0 && !s.startsWith('--'));

      let hasError = false;
      for (const stmt of statements) {
        try {
          await prisma.$executeRawUnsafe(stmt + ';');
        } catch (err) {
          console.error(`Error in ${dir}: ${err.message}`);
          hasError = true;
          throw err;
        }
      }

      if (hasError) {
        console.error(`Skipping _prisma_migrations insert for ${dir} due to errors`);
        continue;
      }

      const checksum = Buffer.from(sql.replace(/\s+/g, ' ')).subarray(0, 32).toString('hex');
      const migrationId = dir;
      const escapedId = escapeSql(migrationId);
      const escapedChecksum = escapeSql(checksum);
      const escapedName = escapeSql(migrationId);

      try {
        await prisma.$executeRawUnsafe(
          `INSERT INTO "_prisma_migrations" ("id", "checksum", "finished_at", "migration_name", "logs", "rolled_back_at", "started_at", "applied_steps_count")
           VALUES (${escapedId}, ${escapedChecksum}, NOW(), ${escapedName}, NULL, NULL, NOW(), 1)`
        );
      } catch (err) {
        if (err.message.includes('relation "_prisma_migrations" does not exist')) {
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
          await prisma.$executeRawUnsafe(
            `INSERT INTO "_prisma_migrations" ("id", "checksum", "finished_at", "migration_name", "logs", "rolled_back_at", "started_at", "applied_steps_count")
             VALUES (${escapedId}, ${escapedChecksum}, NOW(), ${escapedName}, NULL, NULL, NOW(), 1)`
          );
        } else {
          throw err;
        }
      }
      console.log(`  OK`);
    }
    console.log('All migrations applied successfully');
  } catch (err) {
    console.error('Migration failed:', err.message);
    process.exit(1);
  } finally {
    await prisma.$disconnect();
  }
}

runMigrations();
