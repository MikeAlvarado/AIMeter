import type { ReactNode } from 'react'
import { cn } from '../../lib/cn'

export function Pill({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <span
      className={cn(
        'inline-flex items-center rounded-full border border-current/20 px-3.5 py-1 text-xs font-medium tracking-wide uppercase',
        className,
      )}
    >
      {children}
    </span>
  )
}
