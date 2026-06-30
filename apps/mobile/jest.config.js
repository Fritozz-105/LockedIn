// jest-expo provides the RN/Expo transform, jsdom environment, and native-module
// mocks (D98). RNTL v14 auto-extends Jest matchers, so no extra setup file.
/** @type {import('jest').Config} */
module.exports = {
  preset: "jest-expo",
  moduleNameMapper: {
    // Stub CSS imports — Metro handles them at build time, tests don't need them.
    "\\.css$": "<rootDir>/jest/css-stub.js",
    // Mirror the tsconfig "@/*" path alias for Jest's resolver.
    "^@/(.*)$": "<rootDir>/src/$1",
  },
};
