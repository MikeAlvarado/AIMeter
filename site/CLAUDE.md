# AIMeter website (`site/`)

The product page, privacy policy and support page the App Store listing
points at. Scaffolded with `npm create vite@latest -- --template react-ts`
and kept close to that: React 19, Vite, TypeScript strict, Tailwind v4
(`@tailwindcss/vite`), `motion` for mount/hover animation,
`react-router-dom` for the three routes, `lucide-react` for glyphs,
self-hosted fonts (`@fontsource/instrument-serif`,
`@fontsource-variable/mona-sans`), `oxlint` for lint. Nothing runs on a
server: the site is static and makes no third-party request (no
analytics, no cookies, no CDN fonts), which the privacy page states.

## Layout

- `index.html` — meta tags (description, Open Graph with an absolute
  `og.png`, Twitter card, `apple-itunes-app` Smart App Banner with the
  App Store id, icons, manifest). `%VITE_BASE_PATH%` / `%VITE_SITE_URL%`
  come from `.env` at build time.
- `src/main.tsx` → `App.tsx` (`MotionConfig reducedMotion="user"` →
  `LanguageProvider` → `BrowserRouter` with `basename` from
  `import.meta.env.BASE_URL`). Routes: `/` (`pages/Home`), `/privacy`,
  `/support`, `*` (`NotFound`).
- `src/i18n/` — `types.ts` (`Dictionary`, `DocPage`, `Feature`…),
  `en.ts` / `es.ts` (`satisfies Dictionary`, so a key missing in one
  language is a compile error), `context.ts` (split value/setter
  contexts, `detectLocale()`), `LanguageProvider.tsx`. The language is
  stored in `localStorage["aimeter.lang"]`; the first visit follows the
  browser language (Spanish if any preferred language starts with `es`,
  else English). It is never in the URL.
- `src/components/layout/` — `Nav` (fixed pill, blur, shrinks after 60 %
  of a viewport; anchors scroll on the home page and navigate to `/#id`
  elsewhere), `MobileMenu`, `LanguageToggle`, `Footer` (lives inside the
  closing card).
- `src/components/sections/` — in page order: `Hero` (pinned with
  `sticky`, the next section slides over it while `useHeroRecede`
  scales and dims the card), `Statement` (word-by-word brighten driven
  by `useScrollProgress`), `Features` (hairline rows, number + title +
  body + points + a phone capture), `Widgets` (dark card: the three
  widget kinds, Lock Screen / Live Activity, widget renders, the
  home-screen capture), `Mac` (`MenuBarStrip`, a CSS illustration of the
  six status-item styles, plus the "build from source" link), `Privacy`
  (four cards + link to `/privacy`), `OpenSource`, `Closing` (dark card
  + footer).
- `src/components/ui/` — `MixedHeading` (`*word*` → accent italic,
  `\n` → line break), `PhoneFrame` (near-black bezel + hairline, same
  treatment as the store frames), `AppStoreBadge` (drawn, not an image),
  `GitHubLink`, `BrandIcons` (Apple and GitHub paths from Simple Icons,
  CC0), `GrainOverlay`, `DotGrid`, `Pill`, `MenuBarStrip`.
- `src/hooks/` — `useLanguage`, `useLocalStorage`
  (`useSyncExternalStore`, cross-tab), `useMediaQuery`,
  `usePrefersReducedMotion`, `useScrolledPast`, `useScrollProgress`
  (rAF, writes styles, never sets state), `useRevealOnScroll`
  (IntersectionObserver one-shot reveal of `[data-reveal]` children;
  reduced motion shows everything at once), `useHeroRecede`,
  `useDocumentMeta` (title + description per route).
- `src/lib/site.ts` — the App Store id and URL, GitHub URLs, the support
  email, `CURRENT_VERSION` (bump with each release), section ids.
- `src/styles/globals.css` — Tailwind theme. The palette is the app's
  (`Shared/Theme.swift`): terracotta accent on warm ivory, warm charcoal
  in dark mode via `prefers-color-scheme`. The hero, widgets and closing
  cards use the store backdrop (`night-gradient`) in both schemes.
- `scripts/postbuild.mjs` — after `vite build`: copies `index.html` to
  `privacy/index.html`, `support/index.html` and `404.html` (GitHub
  Pages has no rewrite rules, and App Store Connect and crawlers need a
  real 200 on the privacy and support URLs), writes `sitemap.xml`,
  `robots.txt` and `.nojekyll`.
- `scripts/images.mjs` — turns a `Scripts/store-frames.sh` work dir
  (`raw/`, `widget-shots/`) into the WebP files in `src/assets`.
- `public/` — favicons and `apple-touch-icon.png` from the app icon,
  `icon-192/512.png` + `site.webmanifest`, `og.png` (1200×630, the
  centre crop of the store header asset).

## Content rules

Same posture as the store metadata (see the repo root `CLAUDE.md`, "App
Review posture"): the landing page names no third-party product or
company; it says "your provider". The privacy policy and the support
page do name the hosts and tools (api.anthropic.com, Claude Code), since
a policy that hides where the data goes is not a policy; that is
nominative, factual use, with the not-affiliated line under it. Every
image is a demo-mode capture or a widget render from the store pipeline
(`Scripts/StoreFrames/CLAUDE.md`), so no account names, no brand marks.
Claims on the page must be true of the shipped app; when a feature
changes, the dictionary entry changes with it (both languages). The
Mac app is not on the Mac App Store (unsandboxed); the site says so and
links to the README's build steps.

## Hosting

GitHub Pages, project site, deployed by `.github/workflows/site.yml`
(build + `actions/deploy-pages`) on pushes to `main` that touch `site/`.
`.env` sets `VITE_BASE_PATH=/AIMeter/` and `VITE_SITE_URL`; a custom
domain means setting those to `/` and the domain, adding `public/CNAME`,
and nothing else. URLs for App Store Connect: `<site>/` (marketing),
`<site>/support/` (support), `<site>/privacy/` (privacy policy).
