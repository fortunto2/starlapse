// @ts-check
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

// Static site → dist/, served by a Worker with static assets (wrangler.jsonc). English
// first; the app speaks nine more languages and the site will follow the same list.
export default defineConfig({
  site: 'https://starlapse.app',
  integrations: [sitemap()],
});
