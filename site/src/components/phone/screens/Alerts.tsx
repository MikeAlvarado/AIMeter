import { AnimatePresence, motion } from 'motion/react'
import appIcon from '../../../assets/app-icon.png'
import type { PhoneCopy } from '../../../i18n/types'
import { useTicker } from '../useTicker'
import { fill } from './format'

/**
 * The Lock Screen as AIMeter's alerts reach it: generated on the device,
 * each account's title prefixed with its name. They arrive one after the
 * other, newest on top, then the screen clears and they come again.
 */
export function AlertsScreen({ copy }: { copy: PhoneCopy }) {
  const tick = useTicker(1700) % 5
  const notes = [
    { id: 'near', title: `${copy.personal}: ${fill(copy.nearing, copy.session)}`, body: fill(copy.nearingBody, '85') },
    { id: 'early', title: `${copy.work}: ${fill(copy.refilled, copy.weekly)}`, body: fill(copy.refilledBody, copy.weekly) },
  ]
  const shown = tick === 0 ? [] : tick === 1 ? notes.slice(0, 1) : notes
  return (
    <div className="absolute inset-0 flex flex-col items-center pt-[86px]" style={{ background: 'radial-gradient(110% 80% at 50% 10%, #8a4a30 0%, #3a2219 45%, #120d0b 100%)' }}>
      <span className="text-[19px] font-semibold text-white/85">{copy.date}</span>
      <span className="text-[86px] leading-none font-semibold tracking-tight text-white/90">9:41</span>
      <div className="mt-10 flex w-full flex-col gap-2 px-3">
        <AnimatePresence initial={false}>
          {shown
            .slice()
            .reverse()
            .map((note) => (
              <motion.div
                key={note.id}
                layout
                initial={{ opacity: 0, y: -24, scale: 0.96 }}
                animate={{ opacity: 1, y: 0, scale: 1 }}
                exit={{ opacity: 0, scale: 0.96 }}
                transition={{ type: 'spring', stiffness: 380, damping: 32 }}
                className="flex gap-3 rounded-[22px] p-3 text-white backdrop-blur-xl"
                style={{ background: 'rgba(255,255,255,0.16)' }}
              >
                <img src={appIcon} alt="" className="size-[38px] shrink-0 rounded-[9px]" />
                <div className="flex min-w-0 flex-1 flex-col">
                  <div className="flex items-center justify-between">
                    <span className="text-[15px] font-semibold">{note.title}</span>
                    <span className="ml-2 shrink-0 text-[13px] text-white/60">{copy.now}</span>
                  </div>
                  <span className="text-[15px] leading-snug text-white/90">{note.body}</span>
                </div>
              </motion.div>
            ))}
        </AnimatePresence>
      </div>
    </div>
  )
}
