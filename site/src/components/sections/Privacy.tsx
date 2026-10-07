import { ArrowRight, Eye, KeyRound, ServerOff, Trash2 } from 'lucide-react'
import { Link } from 'react-router-dom'
import { useLanguage } from '../../hooks/useLanguage'
import { useRevealOnScroll } from '../../hooks/useRevealOnScroll'
import { MixedHeading } from '../ui/MixedHeading'

const ICONS = [ServerOff, KeyRound, Eye, Trash2]

export function Privacy() {
  const { t } = useLanguage()
  const ref = useRevealOnScroll<HTMLDivElement>()
  return (
    <section id="privacy" className="px-inset-sm nav:px-inset nav:py-32 py-20">
      <div ref={ref} className="mx-auto flex max-w-6xl flex-col gap-12">
        <div data-reveal className="flex max-w-2xl flex-col gap-4">
          <MixedHeading text={t.privacy.heading} className="text-section leading-[1.02]" />
          <p className="text-ink-2 max-w-md text-lg">{t.privacy.sub}</p>
        </div>
        <ul className="tab:flex-row flex flex-col flex-wrap gap-4">
          {t.privacy.points.map((point, index) => {
            const Icon = ICONS[index] ?? ServerOff
            return (
              <li key={point.title} data-reveal className="bg-card rounded-tile border-hairline tab:basis-[calc(50%-0.5rem)] flex flex-col gap-3 border p-6 shadow-[0_10px_30px_rgba(0,0,0,0.05)]">
                <span className="bg-accent-wash text-accent flex size-9 items-center justify-center rounded-lg">
                  <Icon className="size-[18px]" aria-hidden />
                </span>
                <h3 className="text-ink text-lg font-medium">{point.title}</h3>
                <p className="text-ink-2 text-sm leading-relaxed">{point.body}</p>
              </li>
            )
          })}
        </ul>
        <Link data-reveal to="/privacy" className="text-accent inline-flex items-center gap-1 self-start text-sm font-medium underline-offset-4 hover:underline">
          {t.privacy.cta}
          <ArrowRight className="size-4" aria-hidden />
        </Link>
      </div>
    </section>
  )
}
