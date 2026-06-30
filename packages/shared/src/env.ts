import { z } from "zod";

// Validated environment for the API process. Crash early at boot if anything
// here is missing or malformed (see server.ts).
export const apiEnvSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  PORT: z.coerce.number().int().positive().default(3000),
  // Supabase project URL, e.g. https://abcd.supabase.co — used to derive the
  // JWKS URL and the expected token issuer for JWT verification.
  SUPABASE_URL: z.string().url(),
  // Postgres connection string. Use the Supabase transaction pooler (port 6543)
  // — parameterized queries only, no named prepared statements (D90).
  DATABASE_URL: z.string().url(),
});

export type ApiEnv = z.infer<typeof apiEnvSchema>;
