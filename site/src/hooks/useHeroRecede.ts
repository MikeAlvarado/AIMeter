import { useEffect, type RefObject } from 'react'
import { usePrefersReducedMotion } from './usePrefersReducedMotion'

/** `--radius-shell` in globals.css: the radius every other card has. */
const SHELL_RADIUS = 24

/**
 * The hero is pinned (sticky) while the next section slides over it. Over
 * the first viewport of scroll the card shrinks a little and dims, so the
 * incoming section reads as covering something that is receding. It sits
 * full bleed at rest, so its corners round in as it shrinks, up to the
 * other cards' radius.
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
      card.style.borderRadius = `${Math.round(progress * SHELL_RADIUS)}px`
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
      card.style.removeProperty('border-radius')
    }
  }, [cardRef, reduced])
}
