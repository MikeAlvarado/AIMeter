import { useEffect, useRef } from 'react'
import { usePrefersReducedMotion } from './usePrefersReducedMotion'

interface Options {
  selector?: string
  stagger?: number
  threshold?: number
}

/**
 * One-shot enter reveal: every `[data-reveal]` under the ref starts hidden and
 * slides up into place when the root scrolls into view. Reduced motion shows
 * everything at once.
 */
export function useRevealOnScroll<T extends HTMLElement>({
  selector = '[data-reveal]',
  stagger = 90,
  threshold = 0.15,
}: Options = {}) {
  const ref = useRef<T | null>(null)
  const reduced = usePrefersReducedMotion()

  useEffect(() => {
    const root = ref.current
    if (!root) return
    const targets = Array.from(root.querySelectorAll<HTMLElement>(selector))
    if (targets.length === 0) return
    if (reduced) {
      targets.forEach((target) => target.style.removeProperty('opacity'))
      return
    }
    targets.forEach((target) => {
      target.style.opacity = '0'
      target.style.transform = 'translateY(28px)'
    })
    const observer = new IntersectionObserver(
      (entries) => {
        if (!entries.some((entry) => entry.isIntersecting)) return
        targets.forEach((target, index) => {
          target.style.transition = `opacity 0.9s cubic-bezier(0.22, 1, 0.36, 1) ${index * stagger}ms, transform 0.9s cubic-bezier(0.22, 1, 0.36, 1) ${index * stagger}ms`
          target.style.opacity = '1'
          target.style.transform = 'translateY(0)'
        })
        observer.disconnect()
      },
      { threshold },
    )
    observer.observe(root)
    return () => observer.disconnect()
  }, [reduced, selector, stagger, threshold])

  return ref
}
