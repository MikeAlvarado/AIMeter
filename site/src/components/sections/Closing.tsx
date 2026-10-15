import { useLanguage } from '../../hooks/useLanguage'
import { useRevealOnScroll } from '../../hooks/useRevealOnScroll'
import { AppStoreBadge } from '../ui/AppStoreBadge'
import { GitHubLink } from '../ui/GitHubLink'
import { MacDownloadBadge } from '../ui/MacDownloadBadge'
import { PlusGrid } from '../ui/PlusGrid'
import { GrainOverlay } from '../ui/GrainOverlay'
import { MixedHeading } from '../ui/MixedHeading'
import { Footer } from '../layout/Footer'

/**
 * The page's last word and its footer, full bleed like the hero: flush with
 * the window's sides and bottom, so the page opens and closes on the same
 * dark ground and the same "+" grid (`PlusGrid`).
 */
export function Closing() {
  const { t } = useLanguage()
  const ref = useRevealOnScroll<HTMLDivElement>()
  return (
    <section>
      <div className="night-ground relative flex min-h-[80svh] flex-col overflow-hidden text-ivory">
        <GrainOverlay className="opacity-[0.06]" />
        <div ref={ref} className="relative flex flex-1 flex-col items-center justify-center gap-5 px-6 py-28 text-center">
          {/* The same grid the page opened on, behind the words and not the footer. */}
          <PlusGrid track={ref} calm="40% 28% at 50% 50%" />
          <p data-reveal className="text-blush/70 relative max-w-md text-lg">
            {t.closing.eyebrow}
          </p>
          <MixedHeading data-reveal text={t.closing.heading} className="text-hero text-ivory relative max-w-3xl leading-[1.02] [text-shadow:0_0_34px_rgba(243,217,204,0.3)]" />
          <div data-reveal className="relative mt-4 flex flex-wrap items-center justify-center gap-3">
            <AppStoreBadge light />
            <MacDownloadBadge />
            <GitHubLink className="text-ivory border-white/30 hover:bg-white/10">{t.closing.github}</GitHubLink>
          </div>
        </div>
        <Footer />
      </div>
    </section>
  )
}
