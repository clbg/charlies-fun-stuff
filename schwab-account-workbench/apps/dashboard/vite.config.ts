import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import { viteSingleFile } from "vite-plugin-singlefile";

// Static, dependency-light dashboard. The single-file plugin inlines JS + CSS
// (and the build-time-bundled data) into one dist/index.html so it opens with a
// double-click from file:// — no server, matching the original viewer's ergonomics.
export default defineConfig({
  base: "./",
  plugins: [react(), tailwindcss(), viteSingleFile()],
  test: {
    globals: true,
    environment: "node",
  },
});
