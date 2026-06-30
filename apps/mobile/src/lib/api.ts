import { healthResponseSchema, type HealthResponse } from "@lockedin/shared";

import { API_URL } from "./config";

// Minimal typed fetch for the /health roundtrip. The response is validated
// against the SAME zod schema the API uses (imported from @lockedin/shared),
// so the client and server provably can't drift — this is the type-sharing
// contract exercised across the whole stack.
//
// The full auth-aware client (singleton getSession / 401-retry, D65) lands
// with Supabase; /health needs no auth, so this stays deliberately small.
export async function pingHealth(): Promise<HealthResponse> {
  const res = await fetch(`${API_URL}/health`);
  if (!res.ok) {
    throw new Error(`Health check failed: HTTP ${res.status}`);
  }
  // Treat the network payload as untrusted until the schema validates it.
  const json: unknown = await res.json();
  return healthResponseSchema.parse(json);
}
