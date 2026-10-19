// Renders AIMeter's app icons from code: the notch island in four looks
// (Sunset, the bundle's own; Ivory, Night and Pet, chosen in Settings),
// each with its tinted version for iOS, the Mac's sizes inside the Mac
// icon's shape, the pictures Settings shows, the Dock images the Mac
// swaps in, and the website's favicons.
//
//   node Scripts/AppIcon/render.mjs            write everything in place
//   node Scripts/AppIcon/render.mjs <dir>      only a review sheet into <dir>
//
// Uses the website's own `sharp` (site/node_modules), so run
// `npm --prefix site ci` first on a fresh clone.
import { createRequire } from 'node:module'
import { mkdirSync, rmSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..')
const sharp = createRequire(join(ROOT, 'site', 'package.json'))('sharp')
const S = 1024

// ------------------------------------------------------------ drawing
const C = { terraHi: '#E8987A', terra: '#D97757', yellow: '#F0BF3A', black: '#050505' }
let uid = 0
const id = (p) => `${p}${++uid}`
const linear = (gid, stops, x1 = 0, y1 = 0, x2 = 0, y2 = 1) =>
  `<linearGradient id="${gid}" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}">${stops.map(([o, c, a = 1]) => `<stop offset="${o}" stop-color="${c}" stop-opacity="${a}"/>`).join('')}</linearGradient>`
const radial = (gid, stops, cx, cy, r) =>
  `<radialGradient id="${gid}" cx="${cx}" cy="${cy}" r="${r}">${stops.map(([o, c, a = 1]) => `<stop offset="${o}" stop-color="${c}" stop-opacity="${a}"/>`).join('')}</radialGradient>`
const blur = (fid, sd) => `<filter id="${fid}" x="-60%" y="-60%" width="220%" height="220%"><feGaussianBlur stdDeviation="${sd}"/></filter>`
const dropShadow = (fid, dy, sd, opacity) =>
  `<filter id="${fid}" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur in="SourceAlpha" stdDeviation="${sd}"/><feOffset dy="${dy}"/><feComponentTransfer><feFuncA type="linear" slope="${opacity}"/></feComponentTransfer><feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>`
const roundedRect = (x, y, w, h, r) =>
  `M ${x + r} ${y} H ${x + w - r} A ${r} ${r} 0 0 1 ${x + w} ${y + r} V ${y + h - r} A ${r} ${r} 0 0 1 ${x + w - r} ${y + h} H ${x + r} A ${r} ${r} 0 0 1 ${x} ${y + h - r} V ${y + r} A ${r} ${r} 0 0 1 ${x + r} ${y} Z`
/** The app's sparkle: four points, concave sides. */
function sparkle(cx, cy, R, k = 0.16) {
  const q = R * k
  return `M ${cx} ${cy - R} Q ${cx + q} ${cy - q} ${cx + R} ${cy} Q ${cx + q} ${cy + q} ${cx} ${cy + R} Q ${cx - q} ${cy + q} ${cx - R} ${cy} Q ${cx - q} ${cy - q} ${cx} ${cy - R} Z`
}
const svg = (body, defs) => `<svg xmlns="http://www.w3.org/2000/svg" width="${S}" height="${S}" viewBox="0 0 ${S} ${S}"><defs>${defs}</defs>${body}</svg>`

/** A ground: a wash and a soft light from the top left. */
function ground(kind) {
  const g = id('bg'), l = id('lt')
  const washes = {
    dusk: [[0, '#F2A37E'], [0.45, '#B4627A'], [1, '#2F2A55']],
    ivory: [[0, '#FFFFFF'], [0.55, '#F7F4EC'], [1, '#E9E3D6']],
    night: [[0, '#2B2A31'], [1, '#0E0D11']],
    sky: [[0, '#CFE3F7'], [1, '#8FB6E3']],
    tinted: [[0, '#1A1A1A'], [1, '#000000']],
  }
  return {
    defs: linear(g, washes[kind]) + radial(l, [[0, '#FFFFFF', kind === 'tinted' ? 0.06 : 0.28], [1, '#FFFFFF', 0]], 0.3, 0.12, 0.75),
    body: `<rect width="${S}" height="${S}" fill="url(#${g})"/><rect width="${S}" height="${S}" fill="url(#${l})"/>`,
  }
}

// The tones each look draws the island's content in; the tinted one is
// grayscale, which iOS tints with the user's color.
const COLOR = { pill: C.black, mark: C.terraHi, track: '#FFFFFF', trackOpacity: 0.16, first: C.terraHi, second: C.yellow, rule: 0.26 }
const GRAY = { pill: '#2B2B2B', mark: '#FFFFFF', track: '#FFFFFF', trackOpacity: 0.2, first: '#FFFFFF', second: '#BDBDBD', rule: 0.3 }

function bar(x, y, w, h, f, color, tones) {
  return `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${h / 2}" fill="${tones.track}" fill-opacity="${tones.trackOpacity}"/>` +
    `<rect x="${x}" y="${y}" width="${Math.max(h, w * f)}" height="${h}" rx="${h / 2}" fill="${color}"/>`
}

/** The island: a pill with the sparkle and two bars, the island's line. */
function island(look, tones) {
  const bg = ground(tones === GRAY ? 'tinted' : look)
  let defs = bg.defs, body = bg.body
  const w = 860, h = 320, x = 82, y = 352, d = roundedRect(x, y, w, h, h / 2)
  const sh = id('sh')
  defs += dropShadow(sh, 18, 26, { dusk: 0.42, ivory: 0.26, night: 0.6 }[look])
  if (look === 'night' && tones === COLOR) {
    const gb = id('gb'); defs += blur(gb, 60)
    body += `<path d="${roundedRect(x + 40, y + 40, w - 80, h - 80, 120)}" fill="${C.terra}" opacity="0.35" filter="url(#${gb})"/>`
  }
  body += `<g filter="url(#${sh})"><path d="${d}" fill="${tones.pill}"/></g>`
  if (look === 'night' || tones === GRAY) body += `<path d="${d}" fill="none" stroke="#FFFFFF" stroke-opacity="0.12" stroke-width="4"/>`
  // The line: the mark, then two windows either side of a rule.
  const cy = y + h / 2, pad = 94, sx = x + pad + 56
  body += `<path d="${sparkle(sx, cy, 56)}" fill="${tones.mark}"/>`
  const b1x = sx + 56 + 44, sepX = x + w / 2 + 80, b1w = sepX - 30 - b1x, b2x = sepX + 36, b2w = x + w - pad - b2x
  body += bar(b1x, cy - 32, b1w, 64, 0.62, tones.first, tones)
  body += `<rect x="${sepX}" y="${cy - 52}" width="6" height="104" rx="3" fill="#FFFFFF" fill-opacity="${tones.rule}"/>`
  body += bar(b2x, cy - 32, b2w, 64, 0.78, tones.second, tones)
  return svg(body, defs)
}

// The session pet that stands on the island in Pet: the purple cat in
// sunglasses, as the app draws it (`SessionPet`), each pixel a toy block.
const CAT_COLORS = ['#7F77DD', '#CECBF6', '#F2F1EC', '#121212', '#26215C']
const CAT = ['.0........0.', '.00......00.', '.0100000010.', '.0000000000.', '002333323300', '003330033300', '000004400000', '.0000000000.', '..00000000..', '..00....00..']
const mix = (a, b, t) => '#' + [1, 3, 5].map((i) => Math.round(parseInt(a.slice(i, i + 2), 16) + (parseInt(b.slice(i, i + 2), 16) - parseInt(a.slice(i, i + 2), 16)) * t).toString(16).padStart(2, '0')).join('')
const gray = (hex) => { const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16)); const l = Math.round(0.2126 * r + 0.7152 * g + 0.0722 * b); const h = l.toString(16).padStart(2, '0'); return `#${h}${h}${h}` }

function blockCat(cx, bottom, P, d, toGray) {
  const cells = []
  CAT.forEach((row, y) => [...row].forEach((ch, x) => { if (ch !== '.') cells.push({ x, y, color: toGray ? gray(CAT_COLORS[+ch]) : CAT_COLORS[+ch] }) }))
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
function pet(tones) {
  const bg = ground(tones === GRAY ? 'tinted' : 'sky')
  let defs = bg.defs, body = bg.body
  const x = 132, y = 610, w = 760, h = 260, d = roundedRect(x, y, w, h, h / 2), sh = id('sh')
  defs += dropShadow(sh, 18, 26, 0.3)
  body += `<g filter="url(#${sh})"><path d="${d}" fill="${tones.pill}"/></g>`
  if (tones === GRAY) body += `<path d="${d}" fill="none" stroke="#FFFFFF" stroke-opacity="0.12" stroke-width="4"/>`
  body += `<path d="${sparkle(x + 136, y + h / 2, 52)}" fill="${tones.mark}"/>`
  body += bar(x + 236, y + h / 2 - 32, w - 236 - 84, 64, 0.62, tones.first, tones)
  body += blockCat(600, y + 4, 30, 18, tones === GRAY)
  return svg(body, defs)
}

// ------------------------------------------------------------ the looks
// `alternate` is the iOS alternate icon's name (the bundle's own has none),
// and a look with one also gets a Mac Dock image (`AppIconDock-<key>`);
// both names must match `AppIconChoice`. Sunset is the bundle's own icon:
// `writeAll` draws AppIcon.appiconset and the website's icons from it.
const LOOKS = [
  { key: 'Sunset', draw: (t) => island('dusk', t), alternate: null },
  { key: 'Ivory', draw: (t) => island('ivory', t), alternate: 'AppIcon-Ivory' },
  { key: 'Night', draw: (t) => island('night', t), alternate: 'AppIcon-Night' },
  { key: 'Pet', draw: (t) => pet(t), alternate: 'AppIcon-Pet' },
]

const png = (svgText) => sharp(Buffer.from(svgText)).png().toBuffer()
/** iOS's 1024 has no transparency (App Store Connect refuses one that does). */
const opaque = (buf, size = S) => sharp(buf).resize(size, size).flatten({ background: '#000000' }).png().toBuffer()
const MASK = join(dirname(fileURLToPath(import.meta.url)), 'mac-mask.png')
/** The Mac's shape: the art in an 824-point rounded square, 100 points in, the shape the icon has always had. */
async function macShaped(buf, size) {
  const inner = await sharp(buf).resize(824, 824).png().toBuffer()
  const canvas = await sharp({ create: { width: S, height: S, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } })
    .composite([{ input: inner, left: 100, top: 100 }]).png().toBuffer()
  const shaped = await sharp(canvas).composite([{ input: MASK, blend: 'dest-in' }]).png().toBuffer()
  return sharp(shaped).resize(size, size).png().toBuffer()
}

// Written the way Xcode writes them (a space before each colon), so a save in Xcode changes nothing.
const contents = (images) => JSON.stringify({ images, info: { author: 'xcode', version: 1 } }, null, 2).replace(/": /g, '" : ') + '\n'
const iosEntries = (light, tinted) => [
  { filename: light, idiom: 'universal', platform: 'ios', size: '1024x1024' },
  { appearances: [{ appearance: 'luminosity', value: 'tinted' }], filename: tinted, idiom: 'universal', platform: 'ios', size: '1024x1024' },
]
const MAC_SIZES = [[16, 1], [16, 2], [32, 1], [32, 2], [128, 1], [128, 2], [256, 1], [256, 2], [512, 1], [512, 2]]

async function writeAll() {
  const xc = join(ROOT, 'AIMeter', 'Assets.xcassets')
  const rendered = {}
  for (const look of LOOKS) rendered[look.key] = { color: await png(look.draw(COLOR)), gray: await png(look.draw(GRAY)) }

  // The bundle's own icon: Sunset, on iOS and every Mac size.
  const primary = join(xc, 'AppIcon.appiconset')
  rmSync(primary, { recursive: true, force: true }); mkdirSync(primary)
  await sharp(await opaque(rendered.Sunset.color)).toFile(join(primary, 'ios-light.png'))
  await sharp(await opaque(rendered.Sunset.gray)).toFile(join(primary, 'ios-tinted.png'))
  const macImages = []
  for (const [pt, scale] of MAC_SIZES) {
    const name = `mac-${pt}${scale === 2 ? '@2x' : ''}.png`
    await sharp(await macShaped(rendered.Sunset.color, pt * scale)).toFile(join(primary, name))
    macImages.push({ filename: name, idiom: 'mac', scale: `${scale}x`, size: `${pt}x${pt}` })
  }
  writeFileSync(join(primary, 'Contents.json'), contents([...iosEntries('ios-light.png', 'ios-tinted.png'), ...macImages]))
  // The Watch app's icon: the same picture, which watchOS masks round itself.
  const watch = join(ROOT, 'AIMeterWatch', 'Assets.xcassets', 'AppIcon.appiconset')
  rmSync(watch, { recursive: true, force: true }); mkdirSync(watch, { recursive: true })
  await sharp(await opaque(rendered.Sunset.color)).toFile(join(watch, 'icon.png'))
  writeFileSync(join(watch, 'Contents.json'), contents([{ filename: 'icon.png', idiom: 'universal', platform: 'watchos', size: '1024x1024' }]))

  for (const look of LOOKS) {
    // The alternates iOS switches to.
    if (look.alternate) {
      const dir = join(xc, `${look.alternate}.appiconset`)
      rmSync(dir, { recursive: true, force: true }); mkdirSync(dir)
      await sharp(await opaque(rendered[look.key].color)).toFile(join(dir, 'ios.png'))
      await sharp(await opaque(rendered[look.key].gray)).toFile(join(dir, 'ios-tinted.png'))
      writeFileSync(join(dir, 'Contents.json'), contents(iosEntries('ios.png', 'ios-tinted.png')))
      // The Mac's Dock image for it, in the Mac's shape.
      const dock = join(xc, `AppIconDock-${look.key}.imageset`)
      rmSync(dock, { recursive: true, force: true }); mkdirSync(dock)
      await sharp(await macShaped(rendered[look.key].color, S)).toFile(join(dock, 'dock.png'))
      writeFileSync(join(dock, 'Contents.json'), contents([{ filename: 'dock.png', idiom: 'mac' }]))
    }
    // The picture Settings shows for it, full bleed (the view rounds it).
    const preview = join(xc, `AppIconPreview-${look.key}.imageset`)
    rmSync(preview, { recursive: true, force: true }); mkdirSync(preview)
    await sharp(rendered[look.key].color).resize(256, 256).flatten({ background: '#000000' }).png().toFile(join(preview, 'preview.png'))
    writeFileSync(join(preview, 'Contents.json'), contents([{ filename: 'preview.png', idiom: 'universal' }]))
  }

  // The website's icons: Sunset, full bleed.
  const site = join(ROOT, 'site')
  for (const [file, size] of [['public/favicon-32.png', 32], ['public/apple-touch-icon.png', 180], ['public/icon-192.png', 192], ['public/icon-512.png', 512], ['src/assets/app-icon.png', 512]]) {
    await sharp(await opaque(rendered.Sunset.color, size)).toFile(join(site, file))
  }
  console.log('wrote the app icons, the alternates, the previews, the Dock images and the site icons')
}

/** A review sheet: every look in color and tinted, the Mac's shape, and small sizes. */
async function sheet(out) {
  mkdirSync(out, { recursive: true })
  const round = (size) => Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}"><rect width="${size}" height="${size}" rx="${size * 0.2237}" fill="#fff"/></svg>`)
  const masked = async (buf, size) => sharp(buf).resize(size, size).composite([{ input: round(size), blend: 'dest-in' }]).png().toBuffer()
  const comps = []
  let text = ''
  const col = 300
  for (const [i, look] of LOOKS.entries()) {
    const color = await png(look.draw(COLOR)), grayBuf = await png(look.draw(GRAY))
    const y = 40 + i * 320
    comps.push({ input: await masked(color, 260), left: 40, top: y })
    comps.push({ input: await masked(grayBuf, 260), left: 40 + col, top: y })
    comps.push({ input: await macShaped(color, 300), left: 20 + 2 * col, top: y - 20 })
    let x = 40 + 3 * col
    for (const size of [120, 87, 60, 40, 29]) { comps.push({ input: await masked(color, size), left: x, top: y + 260 - size }); x += size + 24 }
    for (const size of [64, 32, 16]) { comps.push({ input: await macShaped(color, size), left: x, top: y + 260 - size }); x += size + 24 }
    text += `<text x="40" y="${y + 290}" font-family="Helvetica Neue" font-size="22" fill="#333">${look.key}</text>`
    await sharp(color).toFile(join(out, `${look.key}.png`))
  }
  const W = 40 + 3 * col + 120 + 87 + 60 + 40 + 29 + 64 + 32 + 16 + 8 * 24 + 40, H = 40 + LOOKS.length * 320
  await sharp({ create: { width: W, height: H, channels: 4, background: '#C9C6BF' } })
    .composite([...comps, { input: Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}">${text}</svg>`) }])
    .png().toFile(join(out, 'sheet.png'))
  console.log('sheet', join(out, 'sheet.png'))
}

if (process.argv[2]) await sheet(process.argv[2])
else await writeAll()
