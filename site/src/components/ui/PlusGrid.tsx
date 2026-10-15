import { useEffect, useMemo, useRef, useState, type CSSProperties, type RefObject } from 'react'
import { usePrefersReducedMotion } from '../../hooks/usePrefersReducedMotion'
import { cn } from '../../lib/cn'

/** Deterministic PRNG (mulberry32): the same grid on every load. */
function rand(seed: number) {
  let t = seed + 0x6d2b79f5
  t = Math.imul(t ^ (t >>> 15), t | 1)
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296
}

/** The cell's side, about; the columns are whatever fits the width. */
const CELL = 48

/**
 * The dark sections' ground, after the author's own portfolio header: a
 * grid of faint "+" marks, each with its own weight and turn, that light
 * up in the accent and spin as the pointer passes, then fade back. The
 * pointer is followed over the whole of `track`, text and demo included,
 * so the trail runs under them too; the grid is calmer behind the
 * section's words (`calm`, an ellipse: its centre and radii in percent of
 * the grid). A device with no pointer twinkles a few cells now and then
 * instead; with reduced motion it stays still. Decorative.
 */
export function PlusGrid({
  track,
  calm = '34% 22% at 50% 27%',
  className,
}: {
  track: RefObject<HTMLElement | null>
  calm?: string
  className?: string
}) {
  const reduced = usePrefersReducedMotion()
  const gridRef = useRef<HTMLDivElement | null>(null)
  const [size, setSize] = useState({ cols: 0, rows: 0 })

  useEffect(() => {
    const grid = gridRef.current
    if (!grid) return
    const observer = new ResizeObserver(([entry]) => {
      if (!entry) return
      const cols = Math.max(6, Math.round(entry.contentRect.width / CELL))
      const rows = Math.max(1, Math.ceil(entry.contentRect.height / (entry.contentRect.width / cols)))
      setSize((current) => (current.cols === cols && current.rows === rows ? current : { cols, rows }))
    })
    observer.observe(grid)
    return () => observer.disconnect()
  }, [])

  const cells = useMemo(
    () =>
      Array.from({ length: size.cols * size.rows }, (_, index) => ({
        grade: Math.floor(rand(index * 3 + 1) * 12 - 6),
        opacity: Math.min(rand(index * 3 + 2), 0.2),
      })),
    [size],
  )

  // The trail: the cell under the pointer lights up at once and is let go
  // a moment later, its own transition easing it back.
  useEffect(() => {
    const area = track.current
    const grid = gridRef.current
    if (!area || !grid || reduced || !size.cols) return
    const timers = new Map<number, number>()
    const light = (index: number) => {
      const cell = grid.children[index]
      if (!cell) return
      cell.classList.add('is-active')
      window.clearTimeout(timers.get(index))
      timers.set(index, window.setTimeout(() => cell.classList.remove('is-active'), 90))
    }
    const move = (event: PointerEvent) => {
      if (event.pointerType !== 'mouse') return
      const rect = grid.getBoundingClientRect()
      const side = rect.width / size.cols
      const col = Math.floor((event.clientX - rect.left) / side)
      const row = Math.floor((event.clientY - rect.top) / side)
      if (col < 0 || row < 0 || col >= size.cols || row >= size.rows) return
      light(row * size.cols + col)
    }
    area.addEventListener('pointermove', move)
    // No pointer to follow: a few cells at a time, every so often.
    const canHover = window.matchMedia('(hover: hover) and (pointer: fine)').matches
    const twinkle = canHover
      ? 0
      : window.setInterval(() => {
          const total = size.cols * size.rows
          for (let n = 0; n < Math.max(1, Math.round(total * 0.03)); n++) light(Math.floor(Math.random() * total))
        }, 600)
    return () => {
      area.removeEventListener('pointermove', move)
      window.clearInterval(twinkle)
      timers.forEach((timer) => window.clearTimeout(timer))
    }
  }, [track, reduced, size])

  return (
    <div
      ref={gridRef}
      aria-hidden
      className={cn('pointer-events-none absolute inset-0 grid content-start overflow-hidden font-mono select-none', className)}
      style={{
        gridTemplateColumns: `repeat(${size.cols || 1}, 1fr)`,
        // Calmer behind the section's words, whole in the margins.
        maskImage: `radial-gradient(ellipse ${calm}, rgb(0 0 0 / 0.3) 45%, black 100%)`,
        WebkitMaskImage: `radial-gradient(ellipse ${calm}, rgb(0 0 0 / 0.3) 45%, black 100%)`,
      }}
    >
      {cells.map((cell, index) => (
        <span key={index} className="plus-cell" style={{ '--grade': cell.grade, '--opacity': cell.opacity } as CSSProperties}>
          +
        </span>
      ))}
    </div>
  )
}
