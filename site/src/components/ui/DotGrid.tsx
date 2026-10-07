import { cn } from '../../lib/cn'

export function DotGrid({ className }: { className?: string }) {
  return <div aria-hidden className={cn('dot-grid pointer-events-none absolute inset-0', className)} />
}
