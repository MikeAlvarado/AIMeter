import { cn } from '../../lib/cn'

const NOISE = `url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='128' height='128'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.8' numOctaves='2' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='128' height='128' filter='url(%23n)'/%3E%3C/svg%3E")`

export function GrainOverlay({ className }: { className?: string }) {
  return (
    <div
      aria-hidden
      className={cn(
        'animate-grain pointer-events-none absolute inset-0 rounded-[inherit] opacity-[0.06] mix-blend-overlay [transform:translateZ(0)]',
        className,
      )}
      style={{ backgroundImage: NOISE, backgroundRepeat: 'repeat' }}
    />
  )
}
