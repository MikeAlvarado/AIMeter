import { useEffect, useState } from 'react'
import { usePrefersReducedMotion } from '../../hooks/usePrefersReducedMotion'

/** A step every `ms` while mounted, for the screens' small live changes; still with reduced motion. */
export function useTicker(ms: number): number {
  const reduced = usePrefersReducedMotion()
  const [tick, setTick] = useState(0)
  useEffect(() => {
    if (reduced) return
    const id = window.setInterval(() => setTick((value) => value + 1), ms)
    return () => window.clearInterval(id)
  }, [ms, reduced])
  return tick
}
