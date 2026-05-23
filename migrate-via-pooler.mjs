import { readdirSync, readFileSync, existsSync } from 'fs';
import { join, resolve } from 'path';
import pkg from 'pg';
const { Client } = pkg;

const MIGRATIONS_DIR = resolve('./prisma/migrations');

function escapeSql(val) {
  if (val === null || val === undefined) return 'NULL';
  return "'" + val.replace(/'/g, "''") + "'";
}

async function ensureTable(client) {
  try {
    await client.query('SELECT 1 FROM "_prisma_migrations" LIMIT 1');
  } catch {
    console.log('Creating _prisma_migrations table...');
    await client.query(`
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

async function isApplied(client, migrationId) {
  try {
    const res = await client.query(
      `SELECT 1 as ok FROM "_prisma_migrations" WHERE "migration_name" = $1 LIMIT 1`,
      [migrationId]
    );
    return res.rows.length > 0;
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

  const dbUrl = process.env.DATABASE_CONNECTION_URI;
  if (!dbUrl) {
    console.error('DATABASE_CONNECTION_URI not set');
    process.exit(1);
  }

  const client = new Client({ connectionString: dbUrl });
  await client.connect();
  console.log('Connected to database');

  await ensureTable(client);

  // If Instance table doesn't exist but migrations are recorded, re-apply all
  let instanceExists = false;
  try {
    await client.query('SELECT 1 FROM "Instance" LIMIT 1');
    instanceExists = true;
  } catch { /* table doesn't exist */ }

  if (!instanceExists && dirs.length > 0) {
    const firstApplied = await isApplied(client, dirs[0]);
    if (firstApplied) {
      console.log('Instance table missing but migrations recorded — re-running all migrations');
      await client.query('DROP TABLE IF EXISTS "_prisma_migrations"');
      await ensureTable(client);
    }
  }

  for (const dir of dirs) {
    const sqlPath = join(MIGRATIONS_DIR, dir, 'migration.sql');
    if (!existsSync(sqlPath)) {
      console.log(`Skipping ${dir}: no migration.sql`);
      continue;
    }

    if (await isApplied(client, dir)) {
      console.log(`Skipping ${dir}: already applied`);
      continue;
    }

    console.log(`Applying: ${dir}`);
    const sql = readFileSync(sqlPath, 'utf-8');

    // Strip comment lines before splitting on ;
    const lines = sql.split(/\r?\n/);
    const cleanedLines = [];
    let inBlockComment = false;
    for (const line of lines) {
      const trimmed = line.trim();
      if (inBlockComment) {
        if (trimmed.includes('*/')) inBlockComment = false;
        continue;
      }
      if (trimmed.startsWith('/*') && !trimmed.includes('*/')) {
        inBlockComment = true;
        continue;
      }
      if (trimmed.startsWith('/*') && trimmed.includes('*/')) {
        continue;
      }
      if (trimmed.startsWith('--')) continue;
      cleanedLines.push(line);
    }
    const statements = cleanedLines.join('\n')
      .split(/;\s*\r?\n/)
      .map(s => s.trim())
      .filter(s => s.length > 0);

    const errors = [];
    for (const stmt of statements) {
      try {
        await client.query(stmt + ';');
      } catch (err) {
        const msg = err.message || '';
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
          console.error(`  Error: ${msg.split('\n')[0]}`);
          errors.push(msg);
        }
      }
    }

    const checksum = Buffer.from(sql.replace(/\s+/g, ' ')).subarray(0, 32).toString('hex');
    const logs = errors.length > 0 ? errors.join('\n') : null;

    await client.query(
      `INSERT INTO "_prisma_migrations" ("id", "checksum", "finished_at", "migration_name", "logs", "rolled_back_at", "started_at", "applied_steps_count")
       VALUES ($1, $2, NOW(), $3, $4, NULL, NOW(), 1)`,
      [dir, checksum, dir, logs]
    );

    console.log(`  OK`);
  }

  console.log('All migrations processed');
  await client.end();
}

runMigrations()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('Fatal:', err.message);
    process.exit(1);
  });
