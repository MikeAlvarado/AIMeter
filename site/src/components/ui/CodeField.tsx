import { useEffect, useRef, type RefObject } from 'react'
import { usePrefersReducedMotion } from '../../hooks/usePrefersReducedMotion'
import { cn } from '../../lib/cn'

/**
 * The hero's ground, after midflight's product page (the same author's;
 * its hero's field, rebuilt here for the night ground): code you can
 * barely see, in patches. A click anywhere on `track` drops into it like
 * a drop of water: a splash where it lands, a bright crest in the accent
 * that spreads and fades, scrambling the code it passes, and fainter
 * swells that run out across the field in patches. Nothing moves under
 * reduced motion, and nothing runs while no ripple lives. Decorative.
 */
const CHARS = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
const CELL_W = 12
const CELL_H = 17
const RIPPLE_LIFE = 3.6
/** The code at rest and the swells: the blush, dimmed. */
const MUTED: Rgb = [243, 217, 204]
/** The crest: `ember-2`, the accent on the night ground. */
const ACCENT: Rgb = [224, 139, 109]
/** How strong the code at rest shows. */
const FAINT = 0.05

type Rgb = [number, number, number]
type Ripple = { x: number; y: number; at: number }

const rgba = ([r, g, b]: Rgb, a: number) => `rgba(${r},${g},${b},${a.toFixed(3)})`
const font = (weight: number) => `${weight} 11px ui-monospace, "SF Mono", Menlo, Consolas, monospace`

/** A smooth random field over the grid, 0 to 1: random values blurred three times, stretched. */
function blobsOf(cols: number, rows: number) {
  let a = Float32Array.from({ length: cols * rows }, Math.random)
  for (let pass = 0; pass < 3; pass++) {
    const b = new Float32Array(cols * rows)
    for (let y = 0; y < rows; y++) {
      for (let x = 0; x < cols; x++) {
        let sum = 0
        let count = 0
        for (let dy = -2; dy <= 2; dy++) {
          for (let dx = -2; dx <= 2; dx++) {
            const xx = x + dx
            const yy = y + dy
            if (xx < 0 || yy < 0 || xx >= cols || yy >= rows) continue
            sum += a[yy * cols + xx]!
            count++
          }
        }
        b[y * cols + x] = sum / count
      }
    }
    a = b
  }
  let lo = 1
  let hi = 0
  for (const v of a) {
    lo = Math.min(lo, v)
    hi = Math.max(hi, v)
  }
  for (let i = 0; i < a.length; i++) a[i] = (a[i]! - lo) / (hi - lo || 1)
  return a
}

/** How much of the drop reaches a cell at distance d, t seconds after it landed: [crest, the rest]. */
function dropAt(d: number, t: number, n: number): [number, number] {
  const fade = (tau: number) => Math.exp(-t / tau)
  // the splash: dense where the drop landed, opening as it fades
  const splash = fade(0.9) * Math.exp(-((d / (50 + 150 * t)) ** 2)) * (0.45 + 0.55 * n)
  // the crest: a bright band that spreads, widens, and fades, uneven along its length
  const crestAt = 300 * t ** 0.8
  const crest = fade(1.25) * Math.exp(-(((d - crestAt) / (26 + 18 * t)) ** 2)) * (0.45 + 0.55 * n)
  // the swells: wide, faint waves that run out across the field, only where the patches are
  const swellAt = 640 * t
  const patch = Math.max(0, (n - 0.25) / 0.75)
  const swell = 0.85 * fade(1.6) * Math.exp(-(((d - swellAt) / (110 + 90 * t)) ** 2)) * patch
  return [crest, Math.max(splash, swell)]
}

export function CodeField({ track, className }: { track: RefObject<HTMLElement | null>; className?: string }) {
  const reduced = usePrefersReducedMotion()
  const canvasRef = useRef<HTMLCanvasElement | null>(null)

  useEffect(() => {
    const host = track.current
    const canvas = canvasRef.current
    const ctx = canvas?.getContext('2d')
    const faint = document.createElement('canvas')
    const fctx = faint.getContext('2d')
    if (!host || !canvas || !ctx || !fctx) return

    let width = 0
    let height = 0
    let cols = 0
    let rows = 0
    let dpr = 1
    let chars = new Uint8Array(0)
    let blobs = new Float32Array(0)
    let running = false
    let frame = 0
    const ripples: Ripple[] = []

    const glyph = (i: number) => CHARS.charAt(chars[i] ?? 0)
    // at rest the code shows in patches: each cell's ink follows the same smooth field the swells do
    const restLevel = (i: number) => Math.min(5, Math.round((blobs[i] ?? 0) * 5))
    const restStyle = (level: number) => rgba(MUTED, FAINT * (0.2 + 1.2 * (level / 5)))

    function drawFaint() {
      fctx!.setTransform(dpr, 0, 0, dpr, 0, 0)
      fctx!.clearRect(0, 0, width, height)
      fctx!.font = font(400)
      fctx!.textBaseline = 'middle'
      for (let level = 0; level <= 5; level++) {
        fctx!.fillStyle = restStyle(level)
        for (let y = 0; y < rows; y++) {
          for (let x = 0; x < cols; x++) {
            const i = y * cols + x
            if (restLevel(i) === level) fctx!.fillText(glyph(i), x * CELL_W + 2, y * CELL_H + CELL_H / 2)
          }
        }
      }
    }

    function paint(now: number) {
      ctx!.setTransform(dpr, 0, 0, dpr, 0, 0)
      ctx!.clearRect(0, 0, width, height)
      ctx!.drawImage(faint, 0, 0, width, height)
      while (ripples.length && (now - ripples[0]!.at) / 1000 > RIPPLE_LIFE) ripples.shift()
      if (!ripples.length) return false
      // each lit cell, sorted into a few looks: the crest in the accent (bold at its top), the rest muted
      const buckets = new Map<string, number[]>()
      for (let y = 0; y < rows; y++) {
        const py = y * CELL_H + CELL_H / 2
        for (let x = 0; x < cols; x++) {
          const px = x * CELL_W + CELL_W / 2
          const i = y * cols + x
          let crest = 0
          let rest = 0
          for (const r of ripples) {
            const [c, s] = dropAt(Math.hypot(px - r.x, py - r.y), (now - r.at) / 1000, blobs[i] ?? 0)
            if (c > crest) crest = c
            if (s > rest) rest = s
          }
          if (crest < 0.08 && rest < 0.07) continue
          // where the crest runs, the code scrambles; the faint layer keeps the new character
          if (crest > 0.3 && Math.random() < 0.16) {
            chars[i] = (Math.random() * CHARS.length) | 0
            fctx!.clearRect(x * CELL_W, y * CELL_H, CELL_W, CELL_H)
            fctx!.fillStyle = restStyle(restLevel(i))
            fctx!.fillText(glyph(i), x * CELL_W + 2, y * CELL_H + CELL_H / 2)
          }
          const key =
            crest >= rest
              ? `${crest > 0.6 ? 'b' : 'a'}${Math.min(9, Math.round(crest * 9))}`
              : `m${Math.min(9, Math.round(rest * 9))}`
          let list = buckets.get(key)
          if (list === undefined) {
            list = []
            buckets.set(key, list)
          }
          list.push(x, y, i)
        }
      }
      ctx!.textBaseline = 'middle'
      for (const [key, list] of buckets) {
        const level = Number(key.slice(1)) / 9
        const accent = key[0] !== 'm'
        ctx!.font = font(key[0] === 'b' ? 700 : accent ? 500 : 400)
        ctx!.fillStyle = accent ? rgba(ACCENT, 0.18 + 0.82 * level) : rgba(MUTED, FAINT * 0.6 + 0.45 * level)
        for (let k = 0; k < list.length; k += 3) {
          const x = list[k]!
          const y = list[k + 1]!
          ctx!.clearRect(x * CELL_W, y * CELL_H, CELL_W, CELL_H)
          ctx!.fillText(glyph(list[k + 2]!), x * CELL_W + 2, y * CELL_H + CELL_H / 2)
        }
      }
      return true
    }

    function loop(now: number) {
      running = paint(now)
      if (running) frame = requestAnimationFrame(loop)
    }

    function layout() {
      const box = host!.getBoundingClientRect()
      width = Math.max(1, Math.ceil(box.width))
      height = Math.max(1, Math.ceil(box.height))
      dpr = Math.min(2, window.devicePixelRatio || 1)
      for (const c of [canvas!, faint]) {
        c.width = Math.round(width * dpr)
        c.height = Math.round(height * dpr)
      }
      canvas!.style.width = `${width}px`
      canvas!.style.height = `${height}px`
      cols = Math.ceil(width / CELL_W)
      rows = Math.ceil(height / CELL_H)
      chars = Uint8Array.from({ length: cols * rows }, () => (Math.random() * CHARS.length) | 0)
      blobs = blobsOf(cols, rows)
      drawFaint()
      paint(performance.now())
    }

    const onClick = (event: MouseEvent) => {
      if (reduced) return
      const box = host.getBoundingClientRect()
      ripples.push({ x: event.clientX - box.left, y: event.clientY - box.top, at: performance.now() })
      if (ripples.length > 4) ripples.shift()
      if (!running) {
        running = true
        frame = requestAnimationFrame(loop)
      }
    }
    host.addEventListener('click', onClick)

    // the field follows the hero's size
    let pending = 0
    const observer = new ResizeObserver(() => {
      cancelAnimationFrame(pending)
      pending = requestAnimationFrame(() => {
        const box = host.getBoundingClientRect()
        if (Math.ceil(box.width) !== width || Math.ceil(box.height) !== height) layout()
      })
    })
    observer.observe(host)
    layout()

    return () => {
      host.removeEventListener('click', onClick)
      observer.disconnect()
      cancelAnimationFrame(pending)
      cancelAnimationFrame(frame)
    }
  }, [track, reduced])

  return (
    <canvas
      ref={canvasRef}
      aria-hidden="true"
      className={cn(
        'pointer-events-none absolute inset-0 [mask-image:linear-gradient(to_bottom,#000_62%,transparent)]',
        className,
      )}
    />
  )
}
