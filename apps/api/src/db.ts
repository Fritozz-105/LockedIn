import pg from "pg";

import { env } from "./config.js";

// pg is CommonJS; default-import then destructure is the safe ESM interop.
const { Pool } = pg;

// One shared pool for the whole process — never construct a client per request
// (centralized DB client). Points at the Supabase transaction pooler (port 6543),
// so use only parameterized queries, never named prepared statements (D90).
// statement_timeout stops a runaway query from pinning a pooled connection.
export const pool = new Pool({
  connectionString: env.DATABASE_URL,
  statement_timeout: 10_000,
  // Supabase requires TLS; the pooler's cert isn't in Node's default CA bundle.
  ssl: { rejectUnauthorized: false },
});
