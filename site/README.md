# AIMeter website

The product page for AIMeter (`/`), the privacy policy (`/privacy`) and the
support page (`/support`), in English and Spanish. React + Vite +
TypeScript, Tailwind v4, `motion` for the few mount animations. Static:
no analytics, no cookies, self-hosted fonts, no third-party requests.

    npm install
    npm run dev        # http://localhost:5173/AIMeter/
    npm run build      # dist/, plus the per-route copies, sitemap and robots
    npm run lint       # oxlint
    npm run typecheck

`.env` holds where the site is served from (`VITE_BASE_PATH`,
`VITE_SITE_URL`); the GitHub Actions workflow in
`.github/workflows/site.yml` builds and deploys `dist/` to GitHub Pages on
every push to `main` that touches `site/`. See `CLAUDE.md` here for the
structure, the content rules and how the images are made.
