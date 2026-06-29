import Fastify from "fastify";
import {
  apiEnvSchema,
  healthResponseSchema,
  type HealthResponse,
} from "@lockedin/shared";

// Validate environment once at startup; crash early and loudly if it's wrong
// rather than failing mysteriously deep in a request later.
const env = apiEnvSchema.parse(process.env);

// Fastify bundles pino; this gives structured JSON logs out of the box.
const app = Fastify({
  logger: {
    level: env.NODE_ENV === "production" ? "info" : "debug",
  },
});

// GET /health — the first proof the whole stack works end-to-end. The response
// is parsed through the shared schema so the API can never silently drift from
// the contract the mobile client consumes.
app.get("/health", async (): Promise<HealthResponse> => {
  return healthResponseSchema.parse({
    status: "ok",
    service: "lockedin-api",
    timestamp: new Date().toISOString(),
  });
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

// Top-level safety net — surface anything that escapes a try/catch instead of
// dying silently (per the entry-point handler rule).
process.on("unhandledRejection", (reason) => {
  app.log.error({ reason }, "unhandledRejection");
  process.exit(1);
});

void start();
