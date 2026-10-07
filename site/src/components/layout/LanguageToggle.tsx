import { useLanguage } from '../../hooks/useLanguage'
import type { Locale } from '../../i18n/types'
import { cn } from '../../lib/cn'

const LOCALES: Locale[] = ['en', 'es']

export function LanguageToggle({ className, dark = false }: { className?: string; dark?: boolean }) {
  const { lang, setLang, t } = useLanguage()
  return (
    <div
      role="group"
      aria-label={t.nav.langLabel}
      className={cn('flex items-center gap-0.5 rounded-full border border-current/20 p-0.5 text-xs', className)}
    >
      {LOCALES.map((locale) => (
        <button
          key={locale}
          type="button"
          aria-current={lang === locale ? 'true' : undefined}
          onClick={() => setLang(locale)}
          className={cn(
            'rounded-full px-2.5 py-1 font-medium transition-colors',
            lang === locale
              ? dark
                ? 'bg-ivory text-night'
                : 'bg-ink text-bg'
              : 'opacity-60 hover:opacity-100',
          )}
        >
          {locale.toUpperCase()}
        </button>
      ))}
    </div>
  )
}
