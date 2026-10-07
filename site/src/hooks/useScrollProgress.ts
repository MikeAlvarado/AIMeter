import { useEffect, type RefObject } from 'react'

interface Options {
  /** Progress reaches 0 when the element's top hits this fraction of the viewport height. */
  start?: number
  /** Progress reaches 1 when the element's top hits this fraction of the viewport height. */
  end?: number
}

/**
 * Calls `onProgress` with a 0..1 value as the element travels through the
 * viewport. Reads layout once per frame at most and never sets React state,
 * so the caller writes styles straight to the DOM.
 */
export function useScrollProgress(
  ref: RefObject<HTMLElement | null>,
  onProgress: (progress: number) => void,
  { start = 0.9, end = 0.3 }: Options = {},
) {
  useEffect(() => {
    const element = ref.current
    if (!element) return
    let frame = 0
    const update = () => {
      frame = 0
      const rect = element.getBoundingClientRect()
      const height = window.innerHeight
      const from = height * start
      const to = height * end
      const raw = (from - rect.top) / (from - to)
      onProgress(Math.min(1, Math.max(0, raw)))
    }
    const schedule = () => {
      if (frame === 0) frame = window.requestAnimationFrame(update)
    }
    update()
    window.addEventListener('scroll', schedule, { passive: true })
    window.addEventListener('resize', schedule)
    return () => {
      window.removeEventListener('scroll', schedule)
      window.removeEventListener('resize', schedule)
      if (frame) window.cancelAnimationFrame(frame)
    }
  }, [ref, onProgress, start, end])
}
