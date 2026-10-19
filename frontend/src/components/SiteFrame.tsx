import type { ReactNode } from 'react'
import { ConsentBanner } from '../analytics/ConsentBanner'
import { site } from '../site'
import { Footer } from './Footer'
import { Logo } from './Logo'
import styles from './SiteFrame.module.css'

// The frame for every page but the landing: a way home, the page, the footer.
export function SiteFrame({ children }: { children: ReactNode }) {
  return (
    <div className={styles.page}>
      <header className={styles.header}>
        <a href="/" className={styles.brand} aria-label={`${site.name} home`}>
          <Logo />
        </a>
        <a href="/" className={styles.back}>
          Back to {site.name}
        </a>
      </header>
      {children}
      <Footer />
      <ConsentBanner />
    </div>
  )
}
