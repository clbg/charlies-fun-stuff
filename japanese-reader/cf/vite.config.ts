import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// React SPA lives in web/, builds to web/dist (served by the Worker's ASSETS binding).
// During `vite dev`, /api/* is proxied to a locally-running `wrangler dev` on :8787.
export default defineConfig({
  root: "web",
  plugins: [react()],
  build: {
    outDir: "dist",
    emptyOutDir: true,
  },
  server: {
    proxy: {
      "/api": "http://localhost:8787",
    },
  },
});
