import { useLayoutEffect, useRef, useState, type ReactNode } from 'react'
import { cn } from '../../lib/cn'
import { SCREEN, SYSTEM_FONT } from './theme'

/**
 * An iPhone drawn around a live screen: a near-black bezel and a hairline,
 * the store frames' treatment, and the screen laid out at 390 × 844 points
 * and scaled to whatever width the page gives it, with the status bar and
 * the Dynamic Island over whatever the screen shows. The device itself
 * never changes: a caller swaps what is inside it, and the status bar turns
 * light or dark with the screen (`dark`). The screen is one image to
 * assistive tech (`label`).
 */
export function Device({ children, dark = false, background, label, className }: { children: ReactNode; dark?: boolean; background: string; label: string; className?: string }) {
  const screenRef = useRef<HTMLDivElement | null>(null)
  const [scale, setScale] = useState(0)

  useLayoutEffect(() => {
    const screen = screenRef.current
    if (!screen) return
    const observer = new ResizeObserver(([entry]) => {
      if (entry) setScale(entry.contentRect.width / SCREEN.width)
    })
    observer.observe(screen)
    return () => observer.disconnect()
  }, [])

  return (
    <div
      role="img"
      aria-label={label}
      className={cn('relative aspect-[390/844] rounded-[14%/6.6%] bg-[#0b0908] p-[3.2%] shadow-[0_40px_80px_rgba(0,0,0,0.45)] ring-1 ring-white/15', className)}
    >
      <div ref={screenRef} className="relative h-full w-full overflow-hidden rounded-[11.5%/5.4%] transition-colors duration-500" style={{ background }}>
        <div
          aria-hidden
          className="absolute top-0 left-0 origin-top-left"
          style={{ width: SCREEN.width, height: SCREEN.height, transform: `scale(${scale})`, fontFamily: SYSTEM_FONT, opacity: scale ? 1 : 0 }}
        >
          {children}
          <StatusBar dark={dark} />
          <div className="absolute top-[11px] left-1/2 h-[35px] w-[124px] -translate-x-1/2 rounded-full bg-black" />
        </div>
      </div>
    </div>
  )
}

function StatusBar({ dark }: { dark: boolean }) {
  return (
    <div
      className="absolute inset-x-0 top-0 flex h-[54px] items-center justify-between px-[36px] pt-[4px] transition-colors duration-500"
      style={{ color: dark ? '#FFFFFF' : '#000000' }}
    >
      <span className="text-[17px] font-semibold tracking-[-0.2px]">9:41</span>
      <span className="flex items-center gap-[6px]">
        <svg width="18" height="12" viewBox="0 0 18 12" fill="currentColor" aria-hidden>
          <rect x="0" y="8" width="3" height="4" rx="1" />
          <rect x="5" y="5.5" width="3" height="6.5" rx="1" />
          <rect x="10" y="3" width="3" height="9" rx="1" />
          <rect x="15" y="0" width="3" height="12" rx="1" />
        </svg>
        <svg width="16" height="12" viewBox="0 0 16 12" fill="currentColor" aria-hidden>
          <path d="M8 2.6c2.3 0 4.4.9 6 2.4l1.2-1.3C13.3 1.9 10.8.8 8 .8S2.7 1.9.8 3.7L2 5c1.6-1.5 3.7-2.4 6-2.4zm0 3.6c1.3 0 2.5.5 3.4 1.3l1.3-1.3C11.4 5 9.8 4.4 8 4.4S4.6 5 3.3 6.2l1.3 1.3c.9-.8 2.1-1.3 3.4-1.3zm0 3.6c-.4 0-.8.1-1.1.4L8 11.4l1.1-1.2c-.3-.3-.7-.4-1.1-.4z" />
        </svg>
        <svg width="27" height="13" viewBox="0 0 27 13" fill="none" aria-hidden>
          <rect x="0.5" y="0.5" width="23" height="12" rx="3.5" stroke="currentColor" strokeOpacity="0.4" />
          <rect x="2" y="2" width="20" height="9" rx="2" fill="currentColor" />
          <path d="M25 4.5v4c.8-.3 1.3-1.1 1.3-2s-.5-1.7-1.3-2z" fill="currentColor" fillOpacity="0.45" />
        </svg>
      </span>
    </div>
  )
}
