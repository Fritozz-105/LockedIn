// Ambient declarations so TypeScript accepts CSS imports. Metro/the web bundler
// handle these at build time; TS just needs to know the shape. Also covers the
// global.css that NativeWind will introduce later (D55/D96).
declare module "*.css";

declare module "*.module.css" {
  const classes: { readonly [key: string]: string };
  export default classes;
}
