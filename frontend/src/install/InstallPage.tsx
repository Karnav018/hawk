import { track } from '../analytics/ga'
import { HawkEye } from '../components/HawkEye'
import { SiteFrame } from '../components/SiteFrame'
import { STORES } from './install'
import styles from './InstallPage.module.css'

const LABELS = {
  android: { lead: 'Get it on', name: 'Google Play' },
  ios: { lead: 'Download on the', name: 'App Store' },
} as const

// A store Hawk isn't on yet says so, rather than linking to a missing page.
function StoreButton({ store }: { store: keyof typeof LABELS }) {
  const { live, url } = STORES[store]
  const { lead, name } = LABELS[store]
  if (!live || !url) {
    return (
      <span className={styles.store} data-soon aria-disabled="true">
        <span className={styles.lead}>Coming soon to</span>
        <span className={styles.name}>{name}</span>
      </span>
    )
  }
  return (
    <a className={styles.store} href={url} onClick={() => track('store_click', { store })}>
      <span className={styles.lead}>{lead}</span>
      <span className={styles.name}>{name}</span>
    </a>
  )
}

export function InstallPage() {
  return (
    <SiteFrame>
      <main className={styles.main}>
        <HawkEye className={styles.eye} blink />
        <h1 className={styles.title}>Get Hawk</h1>
        <p className={styles.text}>
          Your second memory, on your phone. Ask for any photo, document or voice note in your own words, and Hawk
          finds the actual file.
        </p>
        <div className={styles.stores}>
          <StoreButton store="android" />
          <StoreButton store="ios" />
        </div>
      </main>
    </SiteFrame>
  )
}
