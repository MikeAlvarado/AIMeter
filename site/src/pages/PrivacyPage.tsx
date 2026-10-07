import { useLanguage } from '../hooks/useLanguage'
import { DocPage } from './DocPage'

export function PrivacyPage() {
  const { t } = useLanguage()
  return <DocPage page={t.privacyPage} />
}
