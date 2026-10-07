import { cn } from '../../lib/cn'

interface PhoneFrameProps {
  src: string
  alt: string
  className?: string
  priority?: boolean
}

/** A near-black bezel with a hairline stroke, the same device treatment the store frames use. */
export function PhoneFrame({ src, alt, className, priority = false }: PhoneFrameProps) {
  return (
    <div
      className={cn(
        'relative aspect-[1170/2532] overflow-hidden rounded-[12%/5.5%] bg-[#0b0908] p-[2.6%] shadow-[0_40px_80px_rgba(0,0,0,0.45)] ring-1 ring-white/15',
        className,
      )}
    >
      <img
        src={src}
        alt={alt}
        loading={priority ? 'eager' : 'lazy'}
        fetchPriority={priority ? 'high' : 'auto'}
        decoding="async"
        className="h-full w-full rounded-[10%/4.6%] object-cover"
      />
    </div>
  )
}
