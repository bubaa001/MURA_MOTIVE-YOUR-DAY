import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// API calls in src/api.ts hit https://bubaa.pythonanywhere.com/api/v1 directly.
// These proxies cover leftover relative /api and /media paths during local `npm run dev`.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5175,
    proxy: {
      "/api": "https://bubaa.pythonanywhere.com",
      "/media": "https://bubaa.pythonanywhere.com"
    }
  }
});
