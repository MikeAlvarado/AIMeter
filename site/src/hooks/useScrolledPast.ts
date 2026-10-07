import { useSyncExternalStore } from 'react'

function subscribe(onStoreChange: () => void) {
  window.addEventListener('scroll', onStoreChange, { passive: true })
  return () => window.removeEventListener('scroll', onStoreChange)
}

export function useScrolledPast(fraction = 0.6): boolean {
  return useSyncExternalStore(
    subscribe,
    () => window.scrollY > window.innerHeight * fraction,
    () => false,
  )
}
