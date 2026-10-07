import { createContext } from 'react'
import type { Locale } from './types'

export const STORAGE_KEY = 'aimeter.lang'

export function isLocale(value: string): value is Locale {
  return value === 'en' || value === 'es'
}

export function detectLocale(): Locale {
  if (typeof navigator === 'undefined') return 'en'
  const tags = navigator.languages?.length ? navigator.languages : [navigator.language]
  return tags.some((tag) => tag?.toLowerCase().startsWith('es')) ? 'es' : 'en'
}

export const LanguageValueContext = createContext<Locale>('en')
export const LanguageSetterContext = createContext<(next: Locale) => void>(() => {})
