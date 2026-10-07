import { useLanguage } from '../../hooks/useLanguage'
import { useRevealOnScroll } from '../../hooks/useRevealOnScroll'
import { AppStoreBadge } from '../ui/AppStoreBadge'
import { GitHubLink } from '../ui/GitHubLink'
import { GrainOverlay } from '../ui/GrainOverlay'
import { MixedHeading } from '../ui/MixedHeading'
import { Footer } from '../layout/Footer'

export function Closing() {
  const { t } = useLanguage()
  const ref = useRevealOnScroll<HTMLDivElement>()
  return (
    <section className="p-inset-sm nav:p-inset">
      <div className="rounded-shell night-gradient relative flex min-h-[80svh] flex-col overflow-hidden text-ivory">
        <div aria-hidden className="pointer-events-none absolute inset-0 bg-[radial-gradient(50%_45%_at_50%_30%,rgba(224,139,109,0.35)_0%,transparent_72%)]" />
        <GrainOverlay className="opacity-[0.08]" />
        <div ref={ref} className="relative flex flex-1 flex-col items-center justify-center gap-5 px-6 py-24 text-center">
          <p data-reveal className="text-blush/70 max-w-md text-lg">
            {t.closing.eyebrow}
          </p>
          <MixedHeading data-reveal text={t.closing.heading} className="text-hero text-ivory max-w-3xl leading-[1.02] [text-shadow:0_0_34px_rgba(243,217,204,0.3)]" />
          <div data-reveal className="mt-4 flex flex-wrap items-center justify-center gap-3">
            <AppStoreBadge light />
            <GitHubLink className="text-ivory border-white/30 hover:bg-white/10">{t.closing.github}</GitHubLink>
          </div>
        </div>
        <Footer />
      </div>
    </section>
  )
}
