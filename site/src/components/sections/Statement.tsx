import { Fragment, useCallback, useRef } from 'react'
import { useLanguage } from '../../hooks/useLanguage'
import { usePrefersReducedMotion } from '../../hooks/usePrefersReducedMotion'
import { useScrollProgress } from '../../hooks/useScrollProgress'
import { DotGrid } from '../ui/DotGrid'

/** Each word brightens in turn as the statement scrolls up through the viewport. */
export function Statement() {
  const { t } = useLanguage()
  const reduced = usePrefersReducedMotion()
  const ref = useRef<HTMLParagraphElement | null>(null)
  const words = t.statement.split(' ')

  const onProgress = useCallback(
    (progress: number) => {
      const root = ref.current
      if (!root) return
      const spans = root.querySelectorAll<HTMLElement>('[data-word]')
      const window = 0.35
      spans.forEach((span, index) => {
        const at = (index / spans.length) * (1 - window)
        const local = Math.min(1, Math.max(0, (progress - at) / window))
        span.style.opacity = reduced ? '1' : `${0.18 + local * 0.82}`
      })
    },
    [reduced],
  )
  useScrollProgress(ref, onProgress, { start: 0.85, end: 0.25 })

  return (
    <section className="relative overflow-hidden">
      <DotGrid />
      <div className="nav:px-16 nav:py-44 relative flex items-center justify-center px-6 py-32">
        <p ref={ref} className="font-display text-statement text-ink max-w-[62rem] text-center leading-[1.15]">
          {words.map((word, index) => (
            <Fragment key={`${word}-${index}`}>
              <span data-word className="inline-block">
                {word}
              </span>{' '}
            </Fragment>
          ))}
        </p>
      </div>
    </section>
  )
}
