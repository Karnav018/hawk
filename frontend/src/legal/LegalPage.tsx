import type { ReactNode } from 'react'
import { SiteFrame } from '../components/SiteFrame'
import { site } from '../site'
import styles from './LegalPage.module.css'

type Props = {
  title: string
  updated: string
  /** A few lines for people who read nothing else. */
  summary: ReactNode
  children: ReactNode
}

// Both legal pages: the title and date, the short version, then the full text.
export function LegalPage({ title, updated, summary, children }: Props) {
  return (
    <SiteFrame>
      <main className={styles.main}>
        <h1 className={styles.title}>{title}</h1>
        <p className={styles.updated}>Last updated {updated}</p>

        <section className={styles.summary} aria-labelledby="short-version">
          <h2 id="short-version">The short version</h2>
          {summary}
        </section>

        <div className={styles.body}>{children}</div>
      </main>
    </SiteFrame>
  )
}

export function Email() {
  return <a href={`mailto:${site.email}`}>{site.email}</a>
}
