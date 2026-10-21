import { motion } from 'motion/react'
import type { PhoneCopy } from '../../../i18n/types'
import { AccountCard } from '../parts'
import { useTicker } from '../useTicker'
import { APP, backdrop, tint } from '../theme'
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
      card: (
        <AccountCard
          palette={palette}
          name={copy.personal}
          icon="sparkle"
          plan={copy.plan}
          hero={{ title: copy.weekly, used: 61, color: tint(palette, 61), reset: fill(copy.resetsIn, '3d 3h'), suffix: copy.used }}
          rows={[{ title: copy.session, used: 42, color: tint(palette, 42), reset: '2h 58m' }]}
        />
      ),
    },
    {
      id: 'work',
      card: (
        <AccountCard
          palette={palette}
          name={copy.work}
          icon="briefcase"
          plan={copy.plan}
          hero={{ title: copy.session, used: 73, color: tint(palette, 73), reset: fill(copy.resetsIn, '1h 11m'), suffix: copy.used }}
          rows={[{ title: copy.weekly, used: 28, color: tint(palette, 28), reset: '5d 8h' }]}
          delay={0.16}
        />
      ),
    },
  ]
  const ordered = swapped ? accounts.slice().reverse() : accounts
  const moving = swapped ? 'work' : 'personal'
  return (
    <div className="absolute inset-0 px-5 pt-[118px]" style={{ background: backdrop(palette) }}>
      <div className="flex flex-col gap-4">
        {ordered.map((account) => (
          <motion.div
            key={account.id}
            layout
            transition={{ type: 'spring', stiffness: 260, damping: 30 }}
            animate={{ boxShadow: account.id === moving ? '0 18px 40px rgba(0,0,0,0.55)' : '0 0 0 rgba(0,0,0,0)' }}
            className="rounded-[24px]"
          >
            {account.card}
          </motion.div>
        ))}
      </div>
    </div>
  )
}
