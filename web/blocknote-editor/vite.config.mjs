import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "vite";
import { resolve } from "node:path";

export default defineConfig({
  root: resolve(process.cwd(), "web/blocknote-editor"),
  base: "./",
  plugins: [react(), tailwindcss()],
  build: {
    cssMinify: "esbuild",
    emptyOutDir: true,
    outDir: resolve(process.cwd(), "Sources/PromptProducer/Resources/BlockNoteEditor"),
    rollupOptions: {
      input: resolve(process.cwd(), "web/blocknote-editor/index.html")
    }
  }
});
