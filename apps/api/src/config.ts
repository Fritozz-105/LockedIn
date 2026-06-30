// Load .env in local dev. On Heroku/ECS there is no .env file and the platform
// injects real env vars, so dotenv simply finds nothing — harmless. Must run
// before anything reads process.env.
import "dotenv/config";

import { apiEnvSchema } from "@lockedin/shared";

// Parse + validate the environment once at module load. The whole API imports
// `env` from here, so a bad/missing var crashes the process at boot, not later.
export const env = apiEnvSchema.parse(process.env);
