// GitHub Pages serves static files only, so every route the app knows gets
// its own copy of index.html (a real 200 for the URLs App Store Connect and
// crawlers visit), plus a 404.html copy so any other path still boots the
// app and shows its own not-found page. Sitemap and robots carry the
// absolute URL the build was made for.
import { copyFileSync, mkdirSync, writeFileSync, existsSync } from 'node:fs'
import { resolve } from 'node:path'
import { loadEnv } from 'vite'

const env = loadEnv('production', process.cwd(), 'VITE_')
const siteUrl = (env.VITE_SITE_URL || '').replace(/\/$/, '')
const dist = resolve('dist')
const index = resolve(dist, 'index.html')
if (!existsSync(index)) throw new Error('dist/index.html missing; run vite build first')

const routes = ['privacy', 'support']
for (const route of routes) {
  mkdirSync(resolve(dist, route), { recursive: true })
  copyFileSync(index, resolve(dist, route, 'index.html'))
}
copyFileSync(index, resolve(dist, '404.html'))
writeFileSync(resolve(dist, '.nojekyll'), '')

const today = new Date().toISOString().slice(0, 10)
const urls = ['', ...routes.map((route) => `${route}/`)]
  .map((path) => `  <url><loc>${siteUrl}/${path}</loc><lastmod>${today}</lastmod></url>`)
  .join('\n')
writeFileSync(
  resolve(dist, 'sitemap.xml'),
  `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls}\n</urlset>\n`,
)
writeFileSync(resolve(dist, 'robots.txt'), `User-agent: *\nAllow: /\nSitemap: ${siteUrl}/sitemap.xml\n`)
console.log(`postbuild: ${routes.length} route copies, 404.html, sitemap and robots for ${siteUrl}`)
