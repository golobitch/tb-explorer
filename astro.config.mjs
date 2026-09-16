// @ts-check
import { defineConfig } from 'astro/config';
import tailwindcss from "@tailwindcss/vite";

// https://astro.build/config
export default defineConfig({
  // Set SITE_URL (e.g. https://tb-explorer.example.com) at build time to get
  // absolute canonical and Open Graph URLs.
  site: process.env.SITE_URL || undefined,
  vite: {
    plugins: [tailwindcss()],
  },
});
