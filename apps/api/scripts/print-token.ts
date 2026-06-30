// Dev helper: signs in a Supabase test user (password grant) and prints the
// access token (JWT) so you can curl protected routes:
//   TOKEN=$(pnpm --filter @lockedin/api token)
//   curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/me
import "dotenv/config";

const url = process.env.SUPABASE_URL;
const anonKey = process.env.SUPABASE_ANON_KEY;
const email = process.env.TEST_EMAIL;
const password = process.env.TEST_PASSWORD;

if (!url || !anonKey || !email || !password) {
  console.error(
    "Set SUPABASE_URL, SUPABASE_ANON_KEY, TEST_EMAIL, TEST_PASSWORD in apps/api/.env",
  );
  process.exit(1);
}

const res = await fetch(`${url}/auth/v1/token?grant_type=password`, {
  method: "POST",
  headers: { "Content-Type": "application/json", apikey: anonKey },
  body: JSON.stringify({ email, password }),
});

if (!res.ok) {
  console.error(`Sign-in failed: HTTP ${res.status}\n${await res.text()}`);
  process.exit(1);
}

const data: unknown = await res.json();
const token =
  typeof data === "object" && data !== null && "access_token" in data
    ? (data as { access_token?: unknown }).access_token
    : undefined;

if (typeof token !== "string") {
  console.error("No access_token in sign-in response");
  process.exit(1);
}

// Print only the token so it can be captured into a shell variable.
console.log(token);
