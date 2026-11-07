import { existsSync, readdirSync, writeFileSync } from 'node:fs';

const site = 'https://usevolant.com';
const docs = new URL('../app/docs/', import.meta.url);
// Every docs folder with a page is a route, so new pages are listed without editing this script.
const slugs = readdirSync(docs, { withFileTypes: true })
  .filter((entry) => entry.isDirectory() && existsSync(new URL(`${entry.name}/page.tsx`, docs)))
  .map((entry) => entry.name)
  .sort();
const urls = ['/', '/try', '/docs', ...slugs.map((slug) => `/docs/${slug}`)];

writeFileSync(new URL('../public/sitemap.xml', import.meta.url), [
  '<?xml version="1.0" encoding="UTF-8"?>',
  '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
  ...urls.map((path) => `  <url><loc>${site}${path}</loc></url>`),
  '</urlset>',
  '',
].join('\n'));
writeFileSync(new URL('../public/robots.txt', import.meta.url), [
  'User-agent: *',
  'Allow: /',
  '',
  `Sitemap: ${site}/sitemap.xml`,
  '',
].join('\n'));
