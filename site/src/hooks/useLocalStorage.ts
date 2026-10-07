import { useCallback, useSyncExternalStore } from 'react'

const localListeners = new Set<() => void>()

function readRaw(key: string): string | null {
  try {
    return window.localStorage.getItem(key)
  } catch {
    return null
  }
}

export function useLocalStorage<T extends string>(
  key: string,
  fallback: T,
  isValid: (value: string) => value is T,
): [T, (next: T) => void] {
  const subscribe = useCallback((onStoreChange: () => void) => {
    localListeners.add(onStoreChange)
    window.addEventListener('storage', onStoreChange)
    return () => {
      localListeners.delete(onStoreChange)
      window.removeEventListener('storage', onStoreChange)
    }
  }, [])

  const getSnapshot = useCallback(() => {
    const raw = readRaw(key)
    return raw !== null && isValid(raw) ? raw : fallback
  }, [key, fallback, isValid])

  const value = useSyncExternalStore(subscribe, getSnapshot, () => fallback)

  const setValue = useCallback(
    (next: T) => {
      try {
        window.localStorage.setItem(key, next)
      } catch {
        return
      }
      localListeners.forEach((listener) => listener())
    },
    [key],
  )

  return [value, setValue]
}
