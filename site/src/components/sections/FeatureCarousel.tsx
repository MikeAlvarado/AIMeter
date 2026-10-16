import { ChevronLeft, ChevronRight, type LucideIcon } from 'lucide-react'
import { useEffect, useId, useRef, type RefObject } from 'react'
import { useLanguage } from '../../hooks/useLanguage'
import type { Feature } from '../../i18n/types'
import { cn } from '../../lib/cn'
import { fill } from '../phone/screens/format'

/** Past this, a scroll the page started is taken as over, wherever it got to. */
const STEER_MS = 1200

/** The card whose middle is nearest the middle of the track. */
function centeredCard(track: HTMLElement): number {
  const middle = track.scrollLeft + track.clientWidth / 2
  let nearest = 0
  let distance = Number.POSITIVE_INFINITY
  Array.from(track.children).forEach((child, index) => {
    if (!(child instanceof HTMLElement)) return
    const away = Math.abs(child.offsetLeft + child.offsetWidth / 2 - middle)
    if (away < distance) {
      nearest = index
      distance = away
    }
  })
  return nearest
}

/** Where the track scrolls to center its card at `index`; null while it is not shown (from the `tab` breakpoint up). */
function centeringOffset(track: HTMLElement, index: number): number | null {
  const card = track.children[index]
  if (!(card instanceof HTMLElement) || track.clientWidth === 0) return null
  return card.offsetLeft - (track.clientWidth - card.offsetWidth) / 2
}

interface FeatureCarouselProps {
  items: Feature[]
  active: number
  /** Reduced motion: the dot shows no progress and the track jumps rather than glides. */
  reduced: boolean
  /** The phone's panel, whose screen the dots choose. */
  panelId: string
  /** The active dot's fill, which `Features` writes the dwell's progress to. */
  fillRef: RefObject<HTMLSpanElement | null>
  /** A dot, an arrow or a card was tapped, or a card was swiped to the middle. */
  onSelect: (index: number) => void
}

/**
 * The features on a phone, under the iPhone (`Features`): dots that say
 * which screen it shows and jump to another, then the cards, swiped
 * sideways with the next one peeking. The card in the middle is the chosen
 * feature; whatever else chooses one (the dwell, a dot, an arrow, a tap on
 * another card) brings its card to the middle, and the cards it passes on
 * the way choose nothing. With a mouse, or on a tablet, arrows either side
 * of the dots step one card along, round from the last to the first.
 */
export function FeatureCarousel({ items, active, reduced, panelId, fillRef, onSelect }: FeatureCarouselProps) {
  const { t } = useLanguage()
  const trackId = useId()
  const trackRef = useRef<HTMLDivElement | null>(null)
  const activeRef = useRef(active)
  /** The card the page is scrolling the track to. */
  const steeringRef = useRef<number | null>(null)
  /** Set when a swipe chose the card, so the track is not scrolled to where it already is. */
  const swipedRef = useRef(false)

  useEffect(() => {
    activeRef.current = active
  }, [active])

  useEffect(() => {
    if (swipedRef.current) {
      swipedRef.current = false
      return
    }
    const track = trackRef.current
    const left = track ? centeringOffset(track, active) : null
    if (!track || left === null || Math.abs(track.scrollLeft - left) < 2) return
    steeringRef.current = active
    track.scrollTo({ left, behavior: reduced ? 'auto' : 'smooth' })
    const timer = window.setTimeout(() => {
      steeringRef.current = null
    }, STEER_MS)
    return () => window.clearTimeout(timer)
  }, [active, reduced])

  // A track that was hidden (a rotation past the breakpoint) or resized comes back on the active card.
  useEffect(() => {
    const track = trackRef.current
    if (!track) return
    const observer = new ResizeObserver(() => {
      const left = centeringOffset(track, activeRef.current)
      if (left === null || Math.abs(track.scrollLeft - left) < 2) return
      steeringRef.current = null
      track.scrollTo({ left, behavior: 'auto' })
    })
    observer.observe(track)
    return () => observer.disconnect()
  }, [])

  const onScroll = () => {
    const track = trackRef.current
    if (!track) return
    const index = centeredCard(track)
    if (steeringRef.current !== null) {
      if (index === steeringRef.current) steeringRef.current = null
      return
    }
    if (index === active) return
    swipedRef.current = true
    onSelect(index)
  }

  /** A finger, a wheel or the keys take the track over from a scroll the page started. */
  const takeOver = () => {
    steeringRef.current = null
  }

  /** An arrow, like a dot: one card along, round from the last to the first and back, as the dwell goes. */
  const step = (by: 1 | -1) => onSelect((active + by + items.length) % items.length)

  return (
    // Edge to edge, so the cards slide in from the screen's sides. `--slide`
    // is a card's width, which the row of dots and arrows shares.
    <div className="-mx-inset-sm @container flex flex-col gap-2 [--slide:min(23rem,calc(100cqw-4.5rem))]">
      {/* The arrows keep to the middle card's edges and the dots to the
          middle, with arrows or without them (a phone has none). */}
      <div className="mx-auto grid w-(--slide) grid-cols-[1fr_auto_1fr] items-center">
        <Arrow icon={ChevronLeft} label={t.features.carousel.previous} controls={trackId} onClick={() => step(-1)} className="col-start-1 justify-self-start" />
        <div role="tablist" aria-label={t.features.carousel.dots} className="col-start-2 row-start-1 flex justify-center">
          {items.map((item, index) => {
            const selected = index === active
            return (
              <button
                key={item.id}
                type="button"
                role="tab"
                aria-selected={selected}
                aria-controls={panelId}
                aria-label={item.title}
                onClick={() => onSelect(index)}
                className="group flex h-10 items-center px-2.5"
              >
                <span
                  className={cn(
                    'relative h-1.5 overflow-hidden rounded-full transition-[width,background-color] duration-300 motion-reduce:transition-none',
                    selected ? 'bg-accent/30 w-7' : 'bg-ink/20 group-hover:bg-ink/35 w-1.5',
                  )}
                >
                  {selected && (
                    <span ref={fillRef} aria-hidden className="bg-accent absolute inset-0 origin-left" style={{ transform: reduced ? 'none' : 'scaleX(0)' }} />
                  )}
                </span>
              </button>
            )
          })}
        </div>
        <Arrow icon={ChevronRight} label={t.features.carousel.next} controls={trackId} onClick={() => step(1)} className="col-start-3 justify-self-end" />
      </div>
      {/* The spacers before and after let the first and last cards center. */}
      <div
        ref={trackRef}
        id={trackId}
        role="region"
        aria-roledescription={t.features.carousel.role}
        aria-label={t.features.listLabel}
        tabIndex={0}
        onScroll={onScroll}
        onTouchStart={takeOver}
        onWheel={takeOver}
        onKeyDown={takeOver}
        className="relative flex snap-x snap-mandatory gap-3 overflow-x-auto overscroll-x-contain pt-1 pb-6 [scrollbar-width:none] before:w-[calc((100cqw-var(--slide))/2-0.75rem)] before:shrink-0 after:w-[calc((100cqw-var(--slide))/2-0.75rem)] after:shrink-0 focus-visible:outline-offset-[-3px] [&::-webkit-scrollbar]:hidden"
      >
        {items.map((item, index) => {
          const current = index === active
          return (
            // A tap or a click on another card brings it to the middle, as its dot does.
            <div
              key={item.id}
              role="group"
              aria-roledescription={t.features.carousel.slide}
              aria-label={fill(t.features.carousel.position, { n: String(index + 1), total: String(items.length) })}
              onClick={current ? undefined : () => onSelect(index)}
              className={cn(
                'bg-card rounded-tile border-hairline flex w-(--slide) shrink-0 snap-center snap-always flex-col gap-3 border p-5 shadow-[0_8px_24px_rgba(0,0,0,0.05)] transition-opacity duration-300',
                current ? 'opacity-100' : 'cursor-pointer opacity-50 hover:opacity-70',
              )}
            >
              <span className="text-ink-2 text-sm tabular">({String(index + 1).padStart(2, '0')})</span>
              <h3 className="text-ink text-[1.375rem] leading-tight tracking-tight">{item.title}</h3>
              <p className="text-ink/80 text-[0.9375rem] leading-relaxed">{item.body}</p>
              {/* The cards share the tallest one's height: the points keep to the bottom, so a swipe never moves them. */}
              <div className="border-hairline mt-auto border-t pt-4">
                <FeaturePoints points={item.points} />
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}

/**
 * One of the carousel's arrows: shown only where the `arrows` variant holds
 * (a mouse, or a tablet), a round button in the cards' own colors.
 */
function Arrow({ icon: Icon, label, controls, onClick, className }: { icon: LucideIcon; label: string; controls: string; onClick: () => void; className: string }) {
  return (
    <button
      type="button"
      aria-label={label}
      aria-controls={controls}
      onClick={onClick}
      className={cn(
        'arrows:grid bg-card border-hairline text-ink hover:bg-track row-start-1 hidden size-10 place-items-center rounded-full border shadow-[0_4px_14px_rgba(0,0,0,0.06)] transition-[background-color,scale] duration-200 active:scale-95 motion-reduce:transition-none',
        className,
      )}
    >
      <Icon aria-hidden className="size-4.5" />
    </button>
  )
}

/** A feature's points, an accent dot before each: under its row in the list, and in its card. */
export function FeaturePoints({ points }: { points: string[] }) {
  return (
    <ul className="text-ink-2 flex flex-col gap-2 text-sm">
      {points.map((point) => (
        <li key={point} className="flex gap-2.5">
          <span aria-hidden className="bg-accent mt-[0.55em] size-1.5 shrink-0 rounded-full" />
          {point}
        </li>
      ))}
    </ul>
  )
}
