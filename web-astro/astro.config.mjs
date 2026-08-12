import path from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig } from "astro/config";

const rootDir = path.dirname(fileURLToPath(import.meta.url));

export default defineConfig({
  server: {
    host: "127.0.0.1",
    port: 4321,
  },
  vite: {
    resolve: {
      alias: {
        "@zt-ui/stage": path.resolve(rootDir, "../web-stage/src/index.ts"),
      },
    },
    server: {
      fs: {
        allow: [path.resolve(rootDir, "..")],
      },
    },
  },
});
