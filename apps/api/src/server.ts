import { healthResponseSchema, type HealthResponse } from "@lockedin/shared";
import Fastify from "fastify";

import { requireAuth } from "./auth.js";
import { env } from "./config.js";
import { pool } from "./db.js";

// Fastify bundles pino; this gives structured JSON logs out of the box.
const app = Fastify({
  logger: {
    level: env.NODE_ENV === "production" ? "info" : "debug",
  },
});

// GET /health — unauthenticated liveness, validated against the shared schema.
app.get("/health", async (): Promise<HealthResponse> => {
  return healthResponseSchema.parse({
    status: "ok",
    service: "lockedin-api",
    timestamp: new Date().toISOString(),
  });
});

// GET /me — protected. Proves the auth + DB seam end-to-end: verify a Supabase
// JWT (preHandler), then make a real parameterized Postgres roundtrip to confirm
// the token's subject maps to an actual user row.
app.get("/me", { preHandler: requireAuth }, async (req) => {
  const result = await pool.query<{ id: string; email: string | null }>(
    "select id, email from auth.users where id = $1",
    [req.authUser?.id],
  );
  return { token_user: req.authUser, db_user: result.rows[0] ?? null };
});

// Release the pool's connections when Fastify shuts down.
app.addHook("onClose", async () => {
  await pool.end();
});

// Boot. Bind 0.0.0.0 so a container (Docker/Heroku) can route traffic to it.
const start = async (): Promise<void> => {
  try {
    await app.listen({ port: env.PORT, host: "0.0.0.0" });
  } catch (err) {
    app.log.error(err);
    process.exit(1);
  }
};

// Top-level safety net for anything that escapes a try/catch.
process.on("unhandledRejection", (reason) => {
  app.log.error({ reason }, "unhandledRejection");
  process.exit(1);
});

void start();
