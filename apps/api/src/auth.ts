import type { FastifyReply, FastifyRequest } from "fastify";
import { createRemoteJWKSet, jwtVerify } from "jose";

import { env } from "./config.js";

// Supabase publishes its public signing keys here. createRemoteJWKSet fetches +
// caches them and refetches (after a cooldown) when it sees an unknown key id,
// so key rotation needs no redeploy (D29/D64). REQUIRES asymmetric signing keys
// enabled in the Supabase project — with the legacy HS256 default this endpoint
// returns no keys and every verification fails.
const JWKS = createRemoteJWKSet(
  new URL(`${env.SUPABASE_URL}/auth/v1/.well-known/jwks.json`),
);

const ISSUER = `${env.SUPABASE_URL}/auth/v1`;

export interface AuthUser {
  id: string;
  email: string | undefined;
}

// Make the verified user available on every request, set by requireAuth.
declare module "fastify" {
  interface FastifyRequest {
    authUser?: AuthUser;
  }
}

// Verifies the Bearer token and returns the authenticated user. Throws on any
// failure (missing / invalid / expired) — never returns a partial user.
async function verifyBearer(req: FastifyRequest): Promise<AuthUser> {
  const header = req.headers.authorization;
  if (!header?.startsWith("Bearer ")) {
    throw new Error("Missing bearer token");
  }
  const { payload } = await jwtVerify(header.slice("Bearer ".length), JWKS, {
    issuer: ISSUER,
    audience: "authenticated",
  });
  if (!payload.sub) {
    throw new Error("Token has no subject (sub)");
  }
  return {
    id: payload.sub,
    email: typeof payload.email === "string" ? payload.email : undefined,
  };
}

// Fastify preHandler: gate a route behind a valid Supabase JWT. On failure, log
// with context and return 401 — sending a reply here halts the route handler.
export async function requireAuth(
  req: FastifyRequest,
  reply: FastifyReply,
): Promise<void> {
  try {
    req.authUser = await verifyBearer(req);
  } catch (err) {
    req.log.warn({ err }, "JWT verification failed");
    await reply.code(401).send({ error: "Unauthorized" });
  }
}
