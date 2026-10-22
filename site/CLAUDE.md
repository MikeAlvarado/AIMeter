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
  closing section).
- `src/components/sections/` — in page order: `Hero` (full bleed,
  flush with the window's sides and top, and since 3.0 centred on the
  notch: the pills, the headline, the line and the downloads in one
  centred column, and under them `NotchDemo`. All of it fits the first
  screen (Mike's call, 2026-10-16): the opening is `100svh` tall (a
  height of its own, not a minimum, so the demo's room is known; never
  under 36rem), the words above take what they need, their size and
  gaps following the screen's height (`svh` in their clamps), and the
  demo takes the rest. On a phone the GitHub link is left to the end of
  the page, so the two downloads fit on one row. Measured to fit at
  1512×862, 1440×900, 1280×720, 1920×1080, 768×1024 and 390×844. It
  scrolls away with the page; behind all of it, since 4.1, a field of
  code a click ripples, `CodeField`), `Features` (what the app does, in one place:
  the six features and one iPhone whose screen is drawn live, the chosen
  feature's, see `components/phone` below. From the `tab` breakpoint up
  the features are a vertical tab list beside the phone, hairline rows
  with the number and the title, the chosen one opening to its body and
  points. Below it they are `FeatureCarousel`: the iPhone first (narrower
  on a short screen, so what follows fits under it), then dots, a
  tablist whose active dot is a pill that fills with the dwell and
  where a tap jumps, then the features as cards swiped sideways (CSS
  scroll-snap, edge to edge, one card in the middle with the next
  peeking; every card as tall as the tallest, its points kept to the
  bottom under a hairline). On a phone (below the `pad` breakpoint,
  600 px) only the iPhone's top shows, drawn larger (78 % of the width,
  up to 22rem, still yielding to a short screen so the dots and a
  card's title fit under it) and cut 650 pt down its 844 pt screen,
  fading into the page from 545 pt (`edge-fade-b`), below every
  screen's point: the Dashboard's first account, the widgets, History's
  chart and its labels, both alerts, Pace's Forecast card (the lowest,
  ending at 560 pt) and both accounts. Cut, it has no shadow and its
  hairline is drawn inside; a tablet shows it whole. With a mouse or on
  a tablet (the `arrows` variant: `(hover: hover) and (pointer: fine)`,
  or `pad` wide and as tall, so never a phone held either way), arrows
  sit at the middle card's edges with the dots between them; they step
  one card along, round from the last to the first and back, as the
  dwell does. The card in the middle is the chosen feature; whatever
  else chooses one (the dwell, a dot, an arrow, a tap or a click on
  another card) scrolls its card to the middle, and the cards it passes
  on the way don't change the phone. The phone stays put and only its
  screen changes, the new one fading in over the old while the status
  bar turns light or dark with it. It moves on by itself every 7 s, a
  line filling over the active row (the dot on a phone), written
  straight to the element's style rather than through state, so the
  phone isn't drawn again every frame; pointing at it, focusing it or
  scrolling it away pauses it, a touch pauses it until it has left the
  screen (a finger has no hover to leave), and with reduced motion only
  a click, a tap or a swipe changes it and the cards jump rather than
  glide. Since 3.0
  the widgets have no section of their own: they are one of the phone's
  screens, and the page is about a third shorter), `Mac` ("Any Mac, any screen": what the island
  does on a screen without a notch and the status item, `MenuBarStrip`,
  a CSS illustration of the six status-item styles (one line, as in a
  menu bar, wrapping onto two on a phone so none is cut off), four
  extras as short chips and a one-line note (not on the Mac App Store,
  a notarized zip, macOS 14 or later), plus the "Download for Mac" link
  and the "build from source" link;
  the island's three stills it used to show gave way to the hero's
  videos), `Privacy`
  (four cards + link to `/privacy`), `OpenSource`, `Closing` (full
  bleed like the hero, flush with the window's sides and bottom, so the
  page opens and closes on the same dark backdrop: the closing line, the
  downloads and the footer).
- `src/components/ui/` — `MixedHeading` (`*word*` → accent italic,
  `\n` → line break), `AppStoreBadge` (drawn, not an image),
  `MacDownloadBadge` (beside it in the hero and the closing section: the
  accent, a laptop, never the Apple mark — the Mac app is not on the Mac
  App Store; it links to `MAC_DOWNLOAD_URL`, the newest release's
  `AIMeter-macOS.zip`, a name every release keeps so the link never
  needs a bump), `GitHubLink`, `BrandIcons` (Apple and GitHub paths from Simple Icons,
  CC0), `GrainOverlay`, `Pill`, `MenuBarStrip`,
  `PlusGrid` (the dark sections' ground since 3.0, after Mike's own
  portfolio header, in place of the glow from above they had, which
  read as the design reference the page started from: a grid of faint
  ivory "+" marks, a cell about 48 pt, each with its own weight and
  turn from a seeded random, that take the accent and spin as the
  pointer passes and fade back still in the accent; the pointer is
  followed over the whole section, so the trail runs under the text and
  the demo too, written straight to the cells, never through state; the
  grid is calmer behind the section's words, `calm`, an ellipse mask.
  With no pointer a few cells twinkle every 600 ms; with reduced motion
  it stays still. Since 4.1 only the closing has it, behind its words,
  not the footer), `CodeField` (the hero's ground since 4.1, Mike's
  call on 2026-10-22, after the hero of his midflight product page,
  rebuilt for the night ground: a canvas of faint monospace letters and
  digits, 12 × 17 pt cells, shown in patches by a smooth random field; a
  click anywhere on the hero drops into it like a drop of water, a
  splash where it lands, a crest in `ember-2` that spreads, scrambles the
  code it passes and fades, and fainter blush swells that run out over
  the patches, about 3.6 s in all, up to four at once. It draws only
  while a ripple lives, follows the hero's size, fades toward the
  bottom, and with reduced motion stays still),
  and
  `NotchDemo`, the notch island at work the way a product's own demo
  shows it: a MacBook (a near-black bezel, the hinge and the base with
  its groove) playing one scene's recording at a time, the iPhone app
  (`Device` around the live Dashboard) over its lower right from the
  `nav` breakpoint up, and under it the scenes as tabs (Limits, Sessions,
  Needs you, each with a progress underline), nothing more: a scene's
  title is its video's label for assistive tech. It fills the room the
  hero leaves it, a size container (`container-type: size`): the
  MacBook is as wide as the column, or as wide as that room's height
  allows once the hinge, the tabs and the gap are out
  (`--frame`, its height over its width: 16:9 or the phone's 4:3 plus
  the bezel), and the two sit centred in the room. Each video plays to its end and hands over to the next; off
  screen it pauses (an `IntersectionObserver`); with reduced motion
  nothing plays by itself (the poster shows, with the controls). The
  videos are `src/assets/videos/island-<scene>-<lang>.mp4` with a `.webp`
  poster each, one set per language, from `Scripts/island-video.sh` (see
  `Scripts/IslandVideo/CLAUDE.md`). On a phone the screen is cut 4:3
  around the notch (`object-top`), so the island reads at a useful size.
- `src/components/phone/` — the iPhone the page draws instead of showing
  captures, so its screens move and follow the language: `Device` (the
  store frames' near-black bezel and hairline, and the status bar and
  the Dynamic Island over a 390 × 844 pt screen scaled to whatever width
  it gets; one image to assistive tech), `theme.ts` (the app's colors
  from `Shared/Theme.swift`, light and dark, and the usage levels' tint:
  terracotta, yellow above 70 %, red above 85 %), `parts.tsx` (the
  app's pieces: cards, rows whose bars fill and figures count up as they
  appear, account headers, segmented pills, sparklines, the glyphs),
  `useTicker` (the slow counter the screens move by; still under reduced
  motion) and `screens/` (since 4.0 drawn the way 4.0's app is: the
  backdrop, `backdrop()`, the cards' surface, `surface()`, the account
  card with its protagonist, `AccountCard`, the round buttons on glass,
  every figure in `ROUNDED_FONT`, and the 4.0 widgets: Single Limit as
  the protagonist alone, Usage Limits small and All Accounts as the
  card, the medium as columns): `Dashboard`, `Widgets`, `History`, `Pace`,
  `Alerts` and `Accounts`, each the app's own screen in demo mode, its
  names and figures the demo's (the session creeping up while its reset
  counts down, the history drawing each range, the alerts arriving, the
  accounts trading places). Their words are the dictionaries' `phone`
  block, the app's own strings in each language. Drawn, they must stay
  as true to the app as a capture would: its layout, its colors, its
  copy; when a screen changes in the app, its drawing changes with it.
- `src/hooks/` — `useLanguage`, `useLocalStorage`
  (`useSyncExternalStore`, cross-tab), `useMediaQuery`,
  `usePrefersReducedMotion`, `useScrolledPast`, `useRevealOnScroll`
  (IntersectionObserver one-shot reveal of `[data-reveal]` children;
  reduced motion shows everything at once), `useDocumentMeta` (title +
  description per route).
- `src/lib/site.ts` — the App Store id and URL, GitHub URLs, the support
  email, `CURRENT_VERSION` (bump with each release), section ids.
- `src/styles/globals.css` — Tailwind theme. The palette is the app's
  (`Shared/Theme.swift`): terracotta accent on warm ivory, warm charcoal
  in dark mode via `prefers-color-scheme`. The hero and the closing
  section stand on `night-ground` (the night colors from top to bottom,
  a faint warmth low behind what they show, no glow from above), the
  hero with the code field over it and the closing with the "+" grid,
  in both schemes. Breakpoints: `pad` (37.5rem, a
  tablet held upright; below it, a phone), `tab` and `nav`; the
  `arrows` variant (a mouse, or a tablet) shows the features carousel's
  arrows, and `edge-fade-b` fades an element's bottom edge on an eased
  curve from `--fade-from`. The focus ring (`:focus-visible`) sits in
  the base layer, so an element's own utilities win over it: a round
  button keeps its circle, the features track its inset ring.
- `scripts/postbuild.mjs` — after `vite build`: copies `index.html` to
  `privacy/index.html`, `support/index.html` and `404.html` (GitHub
  Pages has no rewrite rules, and App Store Connect and crawlers need a
  real 200 on the privacy and support URLs), writes `sitemap.xml`,
  `robots.txt` and `.nojekyll`.
- `scripts/island.mjs` — turns the notch island captures (two top-edge
  strips and the expanded panel alone, see `Scripts/StoreFrames/CLAUDE.md`
  → "Not store assets") into `island-*.webp` stills, which the page no
  longer shows (the hero's videos replaced them) and posts still use,
  through `Scripts/store-frames.sh <work-dir> notch`.
  `scripts/island-strips.mjs` builds those two strips from the desktop
  picture and the panel captured alone, when the real top edge holds
  windows or other apps' status items.
- `public/` — favicons and `apple-touch-icon.png` from the app icon
  (Sunset, written by the repo's `Scripts/AppIcon/render.mjs`, which
  also writes `src/assets/app-icon.png`, the icon on the drawn alerts),
  `icon-192/512.png` + `site.webmanifest`, `og.png` (1200×630, the
  centre crop of the store header asset).

## Content rules

Short copy (Mike, 2026-10-16): one line for an idea, a sentence or two
at most for a section's lead, two short points under a feature, chips
rather than a list for the Mac's extras. The detail lives on the privacy
and support pages, which keep it whole.

Same posture as the store metadata (see the repo root `CLAUDE.md`, "App
Review posture"): the landing page names no third-party product or
company; it says "your provider". The privacy policy and the support
page do name the hosts and tools (api.anthropic.com, Claude Code), since
a policy that hides where the data goes is not a policy; that is
nominative, factual use, with the not-affiliated line under it. Every
phone screen is drawn with the demo's own names and figures
(`components/phone`), and every video is the real app in demo mode, its
island's sessions the demo's own, over a drawn desktop
(`Scripts/IslandVideo/CLAUDE.md`), so no account names, no brand marks,
no real session.
The support page also carries the Acknowledgments (boring.notch and
Vibe Island, for the notch island's approach and line format — studied,
not copied; see "Open source hygiene" in the repo root `CLAUDE.md`),
again off the landing page.
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
