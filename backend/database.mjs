// Purpose: Reuse the Swift schema and TLS-verified Tiger database from Vercel Functions.
// Side effects: Ordered migrations under the same advisory lock; bounded pooled SQL transactions.
// Inputs: Server-only DATABASE_URL and bundled versioned SQL.
// Outputs: A bounded connection pool and transaction results.
import pg from "pg";
import { readFile } from "node:fs/promises";
let pool, ready;
// MARK: - TLS pool and transaction lifecycle
export function database() {
  if (!pool) {
    const url = new URL(process.env.DATABASE_URL || "");
    if (!["postgres:", "postgresql:"].includes(url.protocol))
      throw new Error("Database configuration missing");
    url.searchParams.delete("sslmode");
    pool = new pg.Pool({
      connectionString: url.toString(),
      ssl: { rejectUnauthorized: true },
      max: 2,
      connectionTimeoutMillis: 5000,
      idleTimeoutMillis: 10000,
      allowExitOnIdle: true,
      query_timeout: 20000,
    });
    pool.on("error", () => {}); // Never log SQL, bind values or connection secrets.
  }
  return pool;
}
export async function transaction(fn) {
  const client = await database().connect();
  try {
    await client.query("BEGIN");
    await client.query("SET LOCAL statement_timeout='15s'");
    const result = await fn(client);
    await client.query("COMMIT");
    return result;
  } catch (error) {
    await client.query("ROLLBACK").catch(() => {});
    throw error;
  } finally {
    client.release();
  }
}
// MARK: - Ordered shared schema and additive Vercel tables
export async function migrate() {
  if (!ready)
    ready = transaction(async (client) => {
      await client.query("SELECT pg_advisory_xact_lock(727382019)");
      await client.query(
        "CREATE TABLE IF NOT EXISTS reva_schema_migrations (version INTEGER PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())",
      );
      const version = Number(
        (
          await client.query(
            "SELECT COALESCE(MAX(version),0) AS version FROM reva_schema_migrations",
          )
        ).rows[0].version,
      );
      if (version > 2) throw new Error("Unsupported schema");
      for (const [index, name] of ["001_snapshot", "002_accounts"].entries()) {
        if (version >= index + 1) continue;
        const sql = await readFile(
          new URL(
            `../server/Sources/RevaServer/Migrations/${name}.sql`,
            import.meta.url,
          ),
          "utf8",
        );
        await client.query(sql);
        await client.query(
          "INSERT INTO reva_schema_migrations(version) VALUES($1)",
          [index + 1],
        );
      }
      // Vercel instances share throttles; keep this additive table outside Swift's migration version sequence.
      await client.query(
        "CREATE TABLE IF NOT EXISTS reva_web_limits (key_hash TEXT PRIMARY KEY, count INTEGER NOT NULL, resets_at TIMESTAMPTZ NOT NULL)",
      );
      await client.query(
        "CREATE TABLE IF NOT EXISTS reva_web_uploads (owner_id TEXT NOT NULL, upload_id TEXT NOT NULL, total INTEGER NOT NULL CHECK(total BETWEEN 1 AND 16777216), bytes BYTEA NOT NULL, expires_at TIMESTAMPTZ NOT NULL DEFAULT now()+interval '1 hour', PRIMARY KEY(owner_id,upload_id))",
      );
    }).catch((error) => {
      ready = null;
      throw error;
    });
  await ready;
}
export async function closeDatabase() {
  if (pool) await pool.end();
  pool = null;
  ready = null;
}
