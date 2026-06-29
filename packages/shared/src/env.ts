import { z } from "zod";

// Validated environment for the API process. Start minimal; extend as services
// land (DATABASE_URL, SUPABASE_* arrive with the DB/auth work, not before).
export const apiEnvSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  PORT: z.coerce.number().int().positive().default(3000),
});

export type ApiEnv = z.infer<typeof apiEnvSchema>;
