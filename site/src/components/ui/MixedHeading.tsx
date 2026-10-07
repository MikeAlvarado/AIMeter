import { createElement, Fragment, type HTMLAttributes, type ReactNode } from 'react'
import { cn } from '../../lib/cn'

interface MixedHeadingProps extends HTMLAttributes<HTMLHeadingElement> {
  text: string
  as?: 'h1' | 'h2' | 'h3'
}

/** `*word*` renders in italic; `\n` breaks the line. */
function parseLine(line: string, keyPrefix: string): ReactNode[] {
  return line.split('*').map((part, index) =>
    index % 2 === 1 ? (
      <em key={`${keyPrefix}-${index}`} className="text-accent italic">
        {part}
      </em>
    ) : (
      part
    ),
  )
}

export function MixedHeading({ text, as = 'h2', className, ...rest }: MixedHeadingProps) {
  const lines = text.split('\n')
  return createElement(
    as,
    { ...rest, className: cn('font-display text-ink', className) },
    lines.map((line, index) => (
      <Fragment key={index}>
        {parseLine(line, `l${index}`)}
        {index < lines.length - 1 && <br />}
      </Fragment>
    )),
  )
}
