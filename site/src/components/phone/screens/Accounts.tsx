import { motion } from 'motion/react'
import type { PhoneCopy } from '../../../i18n/types'
import { AccountHeader, Card, UsageRow } from '../parts'
import { useTicker } from '../useTicker'
import { APP, tint } from '../theme'
import { fill } from './format'

const palette = APP.dark

/**
 * The Dashboard in dark mode, each account under its own icon, and the
 * reorder at work: one card lifts (a shadow, never a bigger card) and
 * takes the other's place, the order every surface follows.
 */
export function AccountsScreen({ copy }: { copy: PhoneCopy }) {
  const swapped = useTicker(2600) % 2 === 1
  const accounts = [
    {
      id: 'personal',
      header: <AccountHeader palette={palette} name={copy.personal} icon="sparkle" plan={copy.plan} />,
      rows: (
        <>
          <UsageRow palette={palette} title={copy.session} used={42} color={tint(palette, 42)} reset={fill(copy.resetsIn, '2h 58m')} />
          <UsageRow palette={palette} title={copy.weekly} used={61} color={tint(palette, 61)} delay={0.08} />
        </>
      ),
    },
    {
      id: 'work',
      header: <AccountHeader palette={palette} name={copy.work} icon="briefcase" plan={copy.plan} />,
      rows: (
        <>
          <UsageRow palette={palette} title={copy.session} used={73} color={tint(palette, 73)} reset={fill(copy.resetsIn, '1h 11m')} delay={0.16} />
          <UsageRow palette={palette} title={copy.weekly} used={28} color={tint(palette, 28)} delay={0.24} />
        </>
      ),
    },
  ]
  const ordered = swapped ? accounts.slice().reverse() : accounts
  const moving = swapped ? 'work' : 'personal'
  return (
    <div className="absolute inset-0 px-4 pt-[110px]" style={{ background: palette.background }}>
      <div className="flex flex-col gap-6">
        {ordered.map((account) => (
          <motion.section key={account.id} layout transition={{ type: 'spring', stiffness: 260, damping: 30 }} className="flex flex-col gap-2">
            {account.header}
            <motion.div
              animate={{ boxShadow: account.id === moving ? '0 18px 40px rgba(0,0,0,0.55)' : '0 0 0 rgba(0,0,0,0)' }}
              transition={{ duration: 0.4 }}
              className="rounded-[20px]"
            >
              <Card palette={palette} className="flex flex-col gap-[14px]">
                {account.rows}
              </Card>
            </motion.div>
          </motion.section>
        ))}
      </div>
    </div>
  )
}
