// Client-side config. Expo inlines EXPO_PUBLIC_* vars into the JS bundle at
// build time. Default to localhost:3000 — reachable directly from the iOS
// simulator. (Android emulator would need 10.0.2.2; physical devices need the
// host LAN IP. Set EXPO_PUBLIC_API_URL to override.)
export const API_URL =
  process.env.EXPO_PUBLIC_API_URL ?? "http://localhost:3000";
