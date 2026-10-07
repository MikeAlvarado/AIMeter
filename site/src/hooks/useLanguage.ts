import { useContext } from 'react'
import { LanguageSetterContext, LanguageValueContext } from '../i18n/context'
import { en } from '../i18n/en'
import { es } from '../i18n/es'
import type { Dictionary, Locale } from '../i18n/types'

const dictionaries: Record<Locale, Dictionary> = { en, es }

export function useLanguage() {
  const lang = useContext(LanguageValueContext)
  const setLang = useContext(LanguageSetterContext)
  return { lang, setLang, t: dictionaries[lang] }
}
