// Babel config so Jest (babel-jest) transforms the app the same way Metro does.
// babel-preset-expo also auto-includes the Reanimated worklets plugin.
module.exports = function (api) {
  api.cache(true);
  return {
    presets: ["babel-preset-expo"],
  };
};
