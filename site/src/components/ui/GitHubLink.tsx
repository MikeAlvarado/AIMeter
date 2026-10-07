import type { ReactNode } from 'react'
import { cn } from '../../lib/cn'
import { GITHUB_URL } from '../../lib/site'
import { GitHubIcon } from './BrandIcons'

export function GitHubLink({ children, className, href = GITHUB_URL }: { children: ReactNode; className?: string; href?: string }) {
  return (
    <a
      href={href}
      target="_blank"
      rel="noreferrer"
      className={cn(
        'inline-flex h-12 items-center gap-2.5 rounded-cta border border-current/25 px-4 text-sm font-medium transition-colors hover:bg-current/10',
        className,
      )}
    >
      <GitHubIcon className="size-5" />
      {children}
    </a>
  )
}
