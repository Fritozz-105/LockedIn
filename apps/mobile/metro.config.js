// Metro config for a pnpm monorepo (D72).
// Without this, Metro only watches apps/mobile and can't resolve hoisted
// dependencies or workspace packages (@lockedin/shared) living at the root.
const { getDefaultConfig } = require("expo/metro-config");
const path = require("path");

const projectRoot = __dirname;
const workspaceRoot = path.resolve(projectRoot, "../..");

const config = getDefaultConfig(projectRoot);

// 1. Watch the whole monorepo so changes in packages/* trigger reloads.
config.watchFolders = [workspaceRoot];

// 2. Resolve modules from the app first, then the hoisted root node_modules.
config.resolver.nodeModulesPaths = [
  path.resolve(projectRoot, "node_modules"),
  path.resolve(workspaceRoot, "node_modules"),
];

// 3. Let Metro resolve .cjs/.mjs sources (zod and friends ship these).
config.resolver.sourceExts.push("cjs", "mjs");

module.exports = config;
