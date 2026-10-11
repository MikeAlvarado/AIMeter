import { Laptop } from 'lucide-react'
import { useLanguage } from '../../hooks/useLanguage'
import { cn } from '../../lib/cn'
import { MAC_DOWNLOAD_URL } from '../../lib/site'

/**
 * The Mac app's notarized zip, straight from the newest GitHub release.
 * Shaped like `AppStoreBadge` beside it but in the accent, with a laptop
 * rather than the Apple mark: the Mac app is not on the Mac App Store,
 * and this must not look like a store badge.
 */
export function MacDownloadBadge({ className }: { className?: string }) {
  const { t } = useLanguage()
  return (
    <a
      href={MAC_DOWNLOAD_URL}
      aria-label={t.hero.macDownload}
      className={cn(
        'bg-accent text-ivory inline-flex h-12 items-center gap-2.5 rounded-cta px-4 transition-transform hover:scale-[1.03]',
        className,
      )}
    >
      <Laptop className="size-6 shrink-0" aria-hidden />
      <span className="flex flex-col leading-none">
        <span className="text-[0.6rem] font-medium tracking-wide opacity-80">{t.hero.macDownloadSmall}</span>
        <span className="text-lg font-semibold tracking-tight">Mac</span>
      </span>
    </a>
  )
}
