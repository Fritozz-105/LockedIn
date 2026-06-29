import { z } from "zod";

// Shape returned by the API's GET /health. Defined once here so the API
// validates its response against it and the mobile client gets the type for
// free — this is the type-sharing contract in miniature.
export const healthResponseSchema = z.object({
  status: z.literal("ok"),
  service: z.string(),
  timestamp: z.string().datetime(),
});

export type HealthResponse = z.infer<typeof healthResponseSchema>;
