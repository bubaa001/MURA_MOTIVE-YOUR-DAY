import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Dev server proxies API + uploaded media to the Django backend, so the React
// app and Django run side by side with zero CORS setup.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5175,
    proxy: {
      "/api": "http://127.0.0.1:8000",
      "/media": "http://127.0.0.1:8000"
    }
  }
});
