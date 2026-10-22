// Renders AIMeter's app icons from code: the notch island in four looks
// (Sunset, the bundle's own; Ivory, Night and Pet, chosen in Settings) as
// Icon Composer documents, layered so the system draws them in Liquid
// Glass (4.0): a ground for light and one for dark, the island as glass,
// the sparkle as glass, the bars, and in Pet the cat. Xcode compiles each
// document into every appearance (light, dark, clear, tinted) and into
// flat images for systems before 26. From the same documents, through
// Xcode's own icon renderer (`ictool`), come the pictures Settings shows,
// the Dock images the Mac swaps in and the website's icons.
//
//   node Scripts/AppIcon/render.mjs            write everything in place
//   node Scripts/AppIcon/render.mjs <dir>      only a review sheet into <dir>
//
// Uses the website's own `sharp` (site/node_modules), so run
// `npm --prefix site ci` first on a fresh clone, and Xcode 26 or later
// (its Icon Composer's `ictool`).
import { createRequire } from 'node:module'
import { execFileSync } from 'node:child_process'
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..')
const sharp = createRequire(join(ROOT, 'site', 'package.json'))('sharp')
const S = 1024
// An app icon's shape inside its canvas on the Mac: 824 of 1024, 100 in.
const DOCK_SHAPE = 824
const DOCK_INSET = (S - DOCK_SHAPE) / 2
const DEVELOPER = execFileSync('xcode-select', ['-p']).toString().trim()
const ICTOOL = join(DEVELOPER, '..', 'Applications', 'Icon Composer.app', 'Contents', 'Executables', 'ictool')

// ------------------------------------------------------------ drawing
const C = { terraHi: '#E8987A', terra: '#D97757', yellow: '#F0BF3A', black: '#050505' }
let uid = 0
const id = (p) => `${p}${++uid}`
const linear = (gid, stops, x1 = 0, y1 = 0, x2 = 0, y2 = 1) =>
  `<linearGradient id="${gid}" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}">${stops.map(([o, c, a = 1]) => `<stop offset="${o}" stop-color="${c}" stop-opacity="${a}"/>`).join('')}</linearGradient>`
const radial = (gid, stops, cx, cy, r) =>
  `<radialGradient id="${gid}" cx="${cx}" cy="${cy}" r="${r}">${stops.map(([o, c, a = 1]) => `<stop offset="${o}" stop-color="${c}" stop-opacity="${a}"/>`).join('')}</radialGradient>`
const roundedRect = (x, y, w, h, r) =>
  `M ${x + r} ${y} H ${x + w - r} A ${r} ${r} 0 0 1 ${x + w} ${y + r} V ${y + h - r} A ${r} ${r} 0 0 1 ${x + w - r} ${y + h} H ${x + r} A ${r} ${r} 0 0 1 ${x} ${y + h - r} V ${y + r} A ${r} ${r} 0 0 1 ${x + r} ${y} Z`
/** The app's sparkle: four points, concave sides. */
function sparkle(cx, cy, R, k = 0.16) {
  const q = R * k
  return `M ${cx} ${cy - R} Q ${cx + q} ${cy - q} ${cx + R} ${cy} Q ${cx + q} ${cy + q} ${cx} ${cy + R} Q ${cx - q} ${cy + q} ${cx - R} ${cy} Q ${cx - q} ${cy - q} ${cx} ${cy - R} Z`
}

const svg = (body, defs = '') => `<svg xmlns="http://www.w3.org/2000/svg" width="${S}" height="${S}" viewBox="0 0 ${S} ${S}"><defs>${defs}</defs>${body}</svg>`

// The grounds: a wash and a soft light from the top left; each look has
// one for light and a deeper one for dark. Clear and tinted icons drop
// them (the system draws its own glass there).
const GROUNDS = {
  dusk: { light: [[0, '#F2A37E'], [0.45, '#B4627A'], [1, '#2F2A55']], dark: [[0, '#4A3346'], [0.5, '#2E2238'], [1, '#121020']] },
  ivory: { light: [[0, '#FFFFFF'], [0.55, '#F7F4EC'], [1, '#E9E3D6']], dark: [[0, '#34322E'], [1, '#1A1918']] },
  night: { light: [[0, '#2B2A31'], [1, '#0E0D11']], dark: [[0, '#222127'], [1, '#08080A']] },
  sky: { light: [[0, '#CFE3F7'], [1, '#8FB6E3']], dark: [[0, '#25344A'], [1, '#111A28']] },
}
function ground(stops, light) {
  const g = id('bg'), l = id('lt')
  return svg(`<rect width="${S}" height="${S}" fill="url(#${g})"/><rect width="${S}" height="${S}" fill="url(#${l})"/>`,
    linear(g, stops) + radial(l, [[0, '#FFFFFF', light], [1, '#FFFFFF', 0]], 0.3, 0.12, 0.75))
}

// The island's colors. The tracks are solid: the system makes a
// translucent white opaque in the dark icon.
const T = { pill: C.black, mark: C.terraHi, track: '#2D2C2B', rule: '#464544', first: C.terraHi, second: C.yellow }

/** The pieces of an island: its pill, its mark, its tracks and rule, and its bars' fills. */
function islandPieces({ x, y, w, h, markX, markR, bars, rule }) {
  const cy = y + h / 2
  return {
    pill: svg(`<path d="${roundedRect(x, y, w, h, h / 2)}" fill="${T.pill}"/>`),
    mark: svg(`<path d="${sparkle(markX, cy, markR)}" fill="${T.mark}"/>`),
    tracks: svg(bars.map((b) => `<rect x="${b.x}" y="${cy - 32}" width="${b.w}" height="64" rx="32" fill="${T.track}"/>`).join('') +
      (rule ? `<rect x="${rule}" y="${cy - 52}" width="6" height="104" rx="3" fill="${T.rule}"/>` : '')),
    fills: svg(bars.map((b) => `<rect x="${b.x}" y="${cy - 32}" width="${Math.max(64, b.w * b.f)}" height="64" rx="32" fill="${b.color}"/>`).join('')),
  }
}

/** The island: a pill with the sparkle and two bars either side of a rule. */
function island() {
  const w = 860, h = 320, x = 82, y = 352, pad = 94, sx = x + pad + 56
  const b1x = sx + 56 + 44, sepX = x + w / 2 + 80, b2x = sepX + 36
  return islandPieces({ x, y, w, h, markX: sx, markR: 56, rule: sepX,
    bars: [{ x: b1x, w: sepX - 30 - b1x, f: 0.62, color: T.first }, { x: b2x, w: x + w - pad - b2x, f: 0.78, color: T.second }] })
}

// The session pet that stands on the island in Pet: the purple cat in
// sunglasses, as the app draws it (`SessionPet`), each pixel a toy block.
const CAT_COLORS = ['#7F77DD', '#CECBF6', '#F2F1EC', '#121212', '#26215C']
const CAT = ['.0........0.', '.00......00.', '.0100000010.', '.0000000000.', '002333323300', '003330033300', '000004400000', '.0000000000.', '..00000000..', '..00....00..']
const mix = (a, b, t) => '#' + [1, 3, 5].map((i) => Math.round(parseInt(a.slice(i, i + 2), 16) + (parseInt(b.slice(i, i + 2), 16) - parseInt(a.slice(i, i + 2), 16)) * t).toString(16).padStart(2, '0')).join('')

function blockCat(cx, bottom, P, d) {
  const cells = []
  CAT.forEach((row, y) => [...row].forEach((ch, x) => { if (ch !== '.') cells.push({ x, y, color: CAT_COLORS[+ch] }) }))
  const has = new Set(cells.map((c) => `${c.x},${c.y}`))
  const x0 = Math.round(cx - (CAT[0].length / 2) * P - d / 2), y0 = bottom - CAT.length * P
  let sides = '', tops = '', fronts = ''
  const e = Math.max(3, Math.round(P * 0.1))
  for (const c of cells) {
    const x = x0 + c.x * P, y = y0 + c.y * P
    if (!has.has(`${c.x + 1},${c.y}`)) sides += `<path d="M ${x + P} ${y + P} L ${x + P + d} ${y + P - d} L ${x + P + d} ${y - d} L ${x + P} ${y} Z" fill="${mix(c.color, '#000000', 0.3)}"/>`
    if (!has.has(`${c.x},${c.y - 1}`)) tops += `<path d="M ${x} ${y} L ${x + d} ${y - d} L ${x + P + d} ${y - d} L ${x + P} ${y} Z" fill="${mix(c.color, '#FFFFFF', 0.24)}"/>`
    fronts += `<rect x="${x}" y="${y}" width="${P + 0.5}" height="${P + 0.5}" fill="${c.color}"/>` +
      `<path d="M ${x} ${y + P} V ${y} H ${x + P} L ${x + P - e} ${y + e} H ${x + e} V ${y + P - e} Z" fill="#FFFFFF" opacity="0.14"/>` +
      `<path d="M ${x + P} ${y} V ${y + P} H ${x} L ${x + e} ${y + P - e} H ${x + P - e} V ${y + e} Z" fill="#000000" opacity="0.07"/>`
  }
  return `<g shape-rendering="crispEdges">${sides}${tops}${fronts}</g>`
}

/** Pet: the island lower, one bar, the cat standing on it. */
function pet() {
  const x = 132, y = 610, w = 760, h = 260
  return { ...islandPieces({ x, y, w, h, markX: x + 136, markR: 52, bars: [{ x: x + 236, w: w - 236 - 84, f: 0.62, color: T.first }] }),
    cat: svg(blockCat(600, y + 4, 30, 18)) }
}

// ------------------------------------------------------------ the looks
// `name` is the document's (and the icon's) name: `AppIcon` is the
// bundle's own, the others the iOS alternates; a look with an alternate
// also gets a Mac Dock image (`AppIconDock-<key>`). Every name must match
// `AppIconChoice`.
const LOOKS = [
  { key: 'Sunset', ground: 'dusk', pieces: island, name: 'AppIcon' },
  { key: 'Ivory', ground: 'ivory', pieces: island, name: 'AppIcon-Ivory' },
  { key: 'Night', ground: 'night', pieces: island, name: 'AppIcon-Night' },
  { key: 'Pet', ground: 'sky', pieces: pet, name: 'AppIcon-Pet' },
]

/** The Icon Composer document for a look: its assets and its icon.json. */
function document(look) {
  const p = look.pieces(), g = GROUNDS[look.ground]
  const assets = { 'ground.svg': ground(g.light, 0.28), 'ground-dark.svg': ground(g.dark, 0.1), 'pill.svg': p.pill, 'mark.svg': p.mark, 'tracks.svg': p.tracks, 'fills.svg': p.fills }
  if (p.cat) assets['cat.svg'] = p.cat
  const hex = (c) => [1, 3, 5].map((i) => (parseInt(c.slice(i, i + 2), 16) / 255).toFixed(5)).join(',')
  const fill = (stops) => ({ 'linear-gradient': [`srgb:${hex(stops[0][1])},1.00000`, `srgb:${hex(stops[stops.length - 1][1])},1.00000`], orientation: { start: { x: 0.5, y: 0 }, stop: { x: 0.5, y: 1 } } })
  const groups = []
  // Top first. The cat stands in front of everything, as solid blocks.
  if (p.cat) groups.push({ name: 'Pet', layers: [{ name: 'cat', 'image-name': 'cat.svg', glass: false }], shadow: { kind: 'neutral', opacity: 0.45 }, translucency: { enabled: false, value: 0 }, specular: false })
  groups.push({ name: 'Line', layers: [
    { name: 'fills', 'image-name': 'fills.svg', glass: false },
    { name: 'mark', 'image-name': 'mark.svg', glass: true },
    { name: 'tracks', 'image-name': 'tracks.svg', glass: false },
  ], shadow: { kind: 'neutral', opacity: 0.4 }, translucency: { enabled: false, value: 0 }, specular: true })
  groups.push({ name: 'Island', layers: [{ name: 'pill', 'image-name': 'pill.svg', glass: true }], shadow: { kind: 'neutral', opacity: 0.55 }, translucency: { enabled: true, value: 0.2 }, specular: true })
  // Ivory's image names can't be specialized per appearance (ictool
  // ignores it), so the dark ground is a layer of its own, each shown in
  // its appearance only.
  groups.push({ name: 'Ground', layers: [
    { name: 'ground-dark', 'image-name': 'ground-dark.svg', glass: false, 'hidden-specializations': [{ value: true }, { appearance: 'dark', value: false }] },
    { name: 'ground', 'image-name': 'ground.svg', glass: false, 'hidden-specializations': [{ value: false }, { appearance: 'dark', value: true }, { appearance: 'tinted', value: true }] },
  ], shadow: { kind: 'none', opacity: 0 }, translucency: { enabled: false, value: 0 }, specular: false })
  const doc = { fill: fill(g.light), 'fill-specializations': [{ appearance: 'dark', value: fill(g.dark) }], groups,
    'supported-platforms': { circles: ['watchOS'], squares: 'shared' } }
  return { assets, json: JSON.stringify(doc, null, 2) + '\n' }
}

function writeDocument(look, dir) {
  const { assets, json } = document(look)
  rmSync(dir, { recursive: true, force: true })
  mkdirSync(join(dir, 'Assets'), { recursive: true })
  for (const [file, text] of Object.entries(assets)) writeFileSync(join(dir, 'Assets', file), text)
  writeFileSync(join(dir, 'icon.json'), json)
}

/** The system's own drawing of a document, through Xcode's `ictool`. */
function render(doc, platform, rendition, size, out) {
  execFileSync(ICTOOL, [doc, '--export-image', '--output-file', out, '--platform', platform, '--rendition', rendition, '--width', `${size}`, '--height', `${size}`, '--scale', '1'], { stdio: 'ignore' })
  return readFileSync(out)
}

// Written the way Xcode writes them (a space before each colon), so a save in Xcode changes nothing.
const contents = (images) => JSON.stringify({ images, info: { author: 'xcode', version: 1 } }, null, 2).replace(/": /g, '" : ') + '\n'

async function writeAll() {
  const xc = join(ROOT, 'AIMeter', 'Assets.xcassets')
  const scratch = mkdtempSync(join(tmpdir(), 'aimeter-icons-'))
  // The flat icons these documents replaced (3.1 to 3.2).
  for (const old of ['AppIcon', 'AppIcon-Ivory', 'AppIcon-Night', 'AppIcon-Pet']) rmSync(join(xc, `${old}.appiconset`), { recursive: true, force: true })
  rmSync(join(ROOT, 'AIMeterWatch', 'Assets.xcassets', 'AppIcon.appiconset'), { recursive: true, force: true })

  for (const look of LOOKS) {
    const doc = join(ROOT, 'AIMeter', `${look.name}.icon`)
    writeDocument(look, doc)
    // The Watch app's icon: Sunset, which watchOS draws round.
    if (look.key === 'Sunset') writeDocument(look, join(ROOT, 'AIMeterWatch', 'AppIcon.icon'))
    // The picture Settings shows for it (the view rounds it again).
    const ios = render(doc, 'iOS', 'Default', S, join(scratch, `${look.key}-ios.png`))
    const preview = join(xc, `AppIconPreview-${look.key}.imageset`)
    rmSync(preview, { recursive: true, force: true }); mkdirSync(preview)
    await sharp(ios).resize(256, 256).png().toFile(join(preview, 'preview.png'))
    writeFileSync(join(preview, 'Contents.json'), contents([{ filename: 'preview.png', idiom: 'universal' }]))
    // The Mac's Dock image for an alternate, as macOS draws it: `ictool`
    // fills the whole canvas with the icon, while an app's icon sits in
    // the middle 824 points of its 1024 with 100 transparent around it
    // (measured on the bundle's own and System Settings'), so the shape is
    // drawn at 824 and set there. Full bleed, it stood a size larger than
    // every other icon in the Dock (Mike, 2026-10-22).
    if (look.key !== 'Sunset') {
      const dock = join(xc, `AppIconDock-${look.key}.imageset`)
      rmSync(dock, { recursive: true, force: true }); mkdirSync(dock)
      const shape = render(doc, 'macOS', 'Default', DOCK_SHAPE, join(scratch, `${look.key}-dock.png`))
      await sharp({ create: { width: S, height: S, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } })
        .composite([{ input: shape, left: DOCK_INSET, top: DOCK_INSET }]).png().toFile(join(dock, 'dock.png'))
      writeFileSync(join(dock, 'Contents.json'), contents([{ filename: 'dock.png', idiom: 'mac' }]))
    }
    // The website's icons: Sunset. The favicon and the page's picture as
    // the system draws it; the home-screen and app icons full bleed and
    // opaque, which the browser or the system rounds itself.
    if (look.key === 'Sunset') {
      const site = join(ROOT, 'site')
      await sharp(ios).resize(32, 32).png().toFile(join(site, 'public/favicon-32.png'))
      await sharp(ios).resize(512, 512).png().toFile(join(site, 'src/assets/app-icon.png'))
      const p = look.pieces(), g = GROUNDS[look.ground]
      const flat = await sharp({ create: { width: S, height: S, channels: 4, background: '#000000' } })
        .composite([ground(g.light, 0.28), p.pill, p.tracks, p.fills, p.mark].map((s) => ({ input: Buffer.from(s) }))).png().toBuffer()
      for (const [file, size] of [['public/apple-touch-icon.png', 180], ['public/icon-192.png', 192], ['public/icon-512.png', 512]]) {
        await sharp(flat).resize(size, size).flatten({ background: '#000000' }).png().toFile(join(site, file))
      }
    }
  }
  rmSync(scratch, { recursive: true, force: true })
  console.log('wrote the icon documents, the Watch\'s, the previews, the Dock images and the site icons')
}

/** A review sheet: every look in every appearance on iOS, and on the Mac. */
async function sheet(out) {
  mkdirSync(out, { recursive: true })
  const scratch = mkdtempSync(join(tmpdir(), 'aimeter-icons-'))
  const RENDITIONS = ['Default', 'Dark', 'ClearLight', 'ClearDark', 'TintedLight', 'TintedDark']
  const cell = 220, comps = []
  let text = ''
  for (const [i, look] of LOOKS.entries()) {
    const doc = join(scratch, `${look.name}.icon`)
    writeDocument(look, doc)
    const y = 40 + i * (cell + 50)
    for (const [j, r] of RENDITIONS.entries()) {
      const buf = render(doc, 'iOS', r, S, join(scratch, `${look.key}-${r}.png`))
      if (r === 'Default') await sharp(buf).toFile(join(out, `${look.key}.png`))
      comps.push({ input: await sharp(buf).resize(cell - 20, cell - 20).png().toBuffer(), left: 40 + j * cell, top: y })
    }
    const mac = render(doc, 'macOS', 'Default', S, join(scratch, `${look.key}-mac.png`))
    comps.push({ input: await sharp(mac).resize(cell - 20, cell - 20).png().toBuffer(), left: 40 + RENDITIONS.length * cell + 20, top: y })
    text += `<text x="40" y="${y + cell + 12}" font-family="Helvetica Neue" font-size="20" fill="#333">${look.key}</text>`
  }
  const W = 80 + (RENDITIONS.length + 1) * cell + 20, H = 40 + LOOKS.length * (cell + 50)
  await sharp({ create: { width: W, height: H, channels: 4, background: '#9A9893' } })
    .composite([...comps, { input: Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}">${text}</svg>`) }])
    .png().toFile(join(out, 'sheet.png'))
  rmSync(scratch, { recursive: true, force: true })
  console.log('sheet', join(out, 'sheet.png'))
}

if (process.argv[2]) await sheet(process.argv[2])
else await writeAll()
