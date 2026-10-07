import { useEffect, useMemo, type ReactNode } from 'react'
import { useLocalStorage } from '../hooks/useLocalStorage'
import { detectLocale, isLocale, LanguageSetterContext, LanguageValueContext, STORAGE_KEY } from './context'
import type { Locale } from './types'

export function LanguageProvider({ children }: { children: ReactNode }) {
  const fallback = useMemo(() => detectLocale(), [])
  const [lang, setLang] = useLocalStorage<Locale>(STORAGE_KEY, fallback, isLocale)

  useEffect(() => {
    document.documentElement.lang = lang
  }, [lang])

  return (
    <LanguageValueContext.Provider value={lang}>
      <LanguageSetterContext.Provider value={setLang}>{children}</LanguageSetterContext.Provider>
    </LanguageValueContext.Provider>
  )
}
