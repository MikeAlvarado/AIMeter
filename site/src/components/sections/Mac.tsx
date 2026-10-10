import { ArrowUpRight } from 'lucide-react'
import islandCollapsed from '../../assets/island-collapsed.webp'
import islandExpanded from '../../assets/island-expanded.webp'
import islandPeek from '../../assets/island-peek.webp'
import { useLanguage } from '../../hooks/useLanguage'
import { useRevealOnScroll } from '../../hooks/useRevealOnScroll'
import { GITHUB_BUILD_URL } from '../../lib/site'
import { MenuBarStrip } from '../ui/MenuBarStrip'
import { MixedHeading } from '../ui/MixedHeading'

const ISLAND_STATES = [
  { src: islandCollapsed, width: 1104, height: 96 },
  { src: islandPeek, width: 1104, height: 96 },
  { src: islandExpanded, width: 1104, height: 527 },
]

export function Mac() {
  const { t } = useLanguage()
  const ref = useRevealOnScroll<HTMLDivElement>()
  return (
    <section className="px-inset-sm nav:px-inset nav:py-32 py-20">
      <div ref={ref} className="nav:flex-row nav:gap-16 mx-auto flex max-w-6xl flex-col gap-10">
        <div data-reveal className="nav:basis-[40%] flex flex-col gap-4">
          <MixedHeading text={t.mac.heading} className="text-section leading-[1.02]" />
          <p className="text-ink-2 max-w-md text-lg">{t.mac.sub}</p>
          <a
            href={GITHUB_BUILD_URL}
            target="_blank"
            rel="noreferrer"
            className="text-accent mt-2 inline-flex items-center gap-1 text-sm font-medium underline-offset-4 hover:underline"
          >
            {t.mac.build}
            <ArrowUpRight className="size-4" aria-hidden />
          </a>
        </div>
        <div className="flex flex-1 flex-col gap-8">
          <div data-reveal className="flex flex-col gap-3">
            {ISLAND_STATES.map((state, i) => (
              <figure key={state.src} className="flex flex-col gap-1.5">
                <img
                  src={state.src}
                  alt={i === 0 ? t.mac.islandAlt : ''}
                  width={state.width}
                  height={state.height}
                  loading="lazy"
                  decoding="async"
                  className="ring-ink/10 w-full rounded-xl ring-1"
                />
                <figcaption className="text-ink-2 text-xs">{t.mac.islandStates[i]}</figcaption>
              </figure>
            ))}
          </div>
          <div data-reveal>
            <MenuBarStrip labels={t.mac.styles} />
          </div>
          <ul data-reveal className="text-ink/80 flex flex-col gap-2 text-sm">
            {t.mac.extras.map((extra) => (
              <li key={extra} className="flex gap-2.5">
                <span aria-hidden className="bg-accent mt-[0.55em] size-1.5 shrink-0 rounded-full" />
                {extra}
              </li>
            ))}
          </ul>
          <p data-reveal className="text-ink-2 text-sm leading-relaxed">
            {t.mac.note}
          </p>
        </div>
      </div>
    </section>
  )
}
