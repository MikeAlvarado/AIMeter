import { useEffect, type RefObject } from 'react'
import { usePrefersReducedMotion } from './usePrefersReducedMotion'

/**
 * The hero is pinned (sticky) while the next section slides over it. Over
 * the first viewport of scroll the card shrinks a little and dims, so the
 * incoming section reads as covering something that is receding.
 */
export function useHeroRecede(cardRef: RefObject<HTMLElement | null>) {
  const reduced = usePrefersReducedMotion()
  useEffect(() => {
    const card = cardRef.current
    if (!card || reduced) return
    let frame = 0
    const update = () => {
      frame = 0
      const progress = Math.min(1, Math.max(0, window.scrollY / window.innerHeight))
      card.style.transform = `scale(${1 - progress * 0.05}) translateY(${progress * 24}px)`
      card.style.opacity = `${1 - progress * 0.45}`
    }
    const schedule = () => {
      if (frame === 0) frame = window.requestAnimationFrame(update)
    }
    update()
    window.addEventListener('scroll', schedule, { passive: true })
    return () => {
      window.removeEventListener('scroll', schedule)
      if (frame) window.cancelAnimationFrame(frame)
      card.style.removeProperty('transform')
      card.style.removeProperty('opacity')
    }
  }, [cardRef, reduced])
}
