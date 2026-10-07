import { useLanguage } from '../../hooks/useLanguage'
import { cn } from '../../lib/cn'
import { APP_STORE_URL } from '../../lib/site'
import { AppleIcon } from './BrandIcons'

/** A link to the App Store listing styled as the familiar black badge, drawn here rather than loaded. */
export function AppStoreBadge({ className, light = false }: { className?: string; light?: boolean }) {
  const { t } = useLanguage()
  return (
    <a
      href={APP_STORE_URL}
      target="_blank"
      rel="noreferrer"
      aria-label={t.hero.appStore}
      className={cn(
        'inline-flex h-12 items-center gap-2.5 rounded-cta px-4 transition-transform hover:scale-[1.03]',
        light ? 'bg-ivory text-night' : 'bg-night text-ivory ring-1 ring-white/20',
        className,
      )}
    >
      <AppleIcon className="size-6 shrink-0" />
      <span className="flex flex-col leading-none">
        <span className="text-[0.6rem] font-medium tracking-wide opacity-80">{t.hero.appStoreSmall}</span>
        <span className="text-lg font-semibold tracking-tight">App Store</span>
      </span>
    </a>
  )
}
