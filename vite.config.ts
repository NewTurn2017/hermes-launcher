import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  // Fixed port so tauri.conf.json devUrl can point at it for `tauri dev`.
  server: { port: 1420, strictPort: true },
  // tauri.conf.json frontendDist = "../dist" -> output to repo-root /dist
  build: { outDir: "dist", emptyOutDir: true },
  test: {
    environment: "jsdom",
    setupFiles: ["./src/setupTests.ts"],
    globals: true,
  },
});
