import { cn } from '../../lib/cn'

/**
 * The six status-item styles, drawn in CSS at menu-bar scale: an
 * illustration of Settings → Menu bar, not a capture.
 */
function Gauge({ pct, className }: { pct: number; className?: string }) {
  const r = 6
  const c = 2 * Math.PI * r
  return (
    <svg aria-hidden viewBox="0 0 16 16" className={cn('size-4', className)}>
      <circle cx="8" cy="8" r={r} fill="none" stroke="currentColor" strokeOpacity="0.25" strokeWidth="2.5" />
      <circle
        cx="8"
        cy="8"
        r={r}
        fill="none"
        stroke="currentColor"
        strokeWidth="2.5"
        strokeDasharray={`${(c * pct) / 100} ${c}`}
        strokeLinecap="round"
        transform="rotate(-90 8 8)"
      />
    </svg>
  )
}

function Bar({ pct, className }: { pct: number; className?: string }) {
  return (
    <span aria-hidden className={cn('inline-flex h-2 w-9 overflow-hidden rounded-full bg-current/25', className)}>
      <span className="h-full rounded-full bg-current" style={{ width: `${pct}%` }} />
    </span>
  )
}

function Battery({ pct, className }: { pct: number; className?: string }) {
  return (
    <span aria-hidden className={cn('relative inline-flex h-3 w-7 items-center rounded-[3px] border border-current/60 p-px', className)}>
      <span className="h-full rounded-[2px] bg-current" style={{ width: `${pct}%` }} />
      <span className="absolute top-1/2 -right-1 h-1.5 w-0.5 -translate-y-1/2 rounded-r bg-current/60" />
    </span>
  )
}

const ITEMS = [
  { key: 'gauge-number', node: <><Gauge pct={58} /><span>58 %</span></> },
  { key: 'gauge', node: <Gauge pct={58} /> },
  { key: 'number', node: <span>58 %</span> },
  { key: 'bar', node: <Bar pct={58} /> },
  { key: 'battery', node: <Battery pct={58} /> },
  { key: 'multi', node: <><span className="opacity-70">S</span><span>58 %</span><span className="opacity-70">W</span><span>39 %</span></> },
  { key: 'danger', node: <><Gauge pct={86} className="text-danger" /><span className="text-danger">86 %</span><span className="opacity-60">2h 14m</span></> },
]

export function MenuBarStrip({ labels }: { labels: string[] }) {
  return (
    <div className="flex flex-col gap-3">
      {[
        { tone: 'bg-[#e9e6e0] text-[#1f1e1d]', key: 'light' },
        { tone: 'bg-[#1e1d1b] text-[#f2f0ea]', key: 'dark' },
      ].map((row) => (
        <div
          key={row.key}
          className={cn('flex items-center gap-5 overflow-x-auto rounded-tile px-5 py-2.5 text-[13px] font-medium tabular whitespace-nowrap', row.tone)}
        >
          {ITEMS.map((item) => (
            <span key={item.key} className="inline-flex items-center gap-1.5">
              {item.node}
            </span>
          ))}
        </div>
      ))}
      <ul className="text-ink-2 flex flex-wrap gap-x-5 gap-y-1 text-sm">
        {labels.map((label) => (
          <li key={label}>{label}</li>
        ))}
      </ul>
    </div>
  )
}
