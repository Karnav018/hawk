import { NAV_REVEAL_PX } from '../components/Nav'
import { useScrolledPast } from '../hooks/useScroll'
import { setConsent, useConsent } from './consent'
import { GA_ID } from './ga'
import styles from './ConsentBanner.module.css'

// Asks once, in the site's own voice. Shown only in the browser (never in
// the prerendered HTML) and only when analytics is configured. `afterFilm`:
// on the landing page it waits until the visitor scrolls past the film, so
// nothing covers the film or its captions.
export function ConsentBanner({ afterFilm = false }: { afterFilm?: boolean }) {
  const consent = useConsent()
  const pastFilm = useScrolledPast(NAV_REVEAL_PX)
  if (!GA_ID || consent !== null || (afterFilm && !pastFilm)) return null

  return (
    <section className={styles.banner} aria-label="Analytics choice">
      <p className={styles.text}>
        Can Hawk count visits with Google Analytics? Cookies are set only if you allow it.{' '}
        <a href="/privacy#this-website">Privacy</a>
      </p>
      <div className={styles.actions}>
        <button type="button" className={styles.no} onClick={() => setConsent('denied')}>
          No thanks
        </button>
        <button type="button" className={styles.yes} onClick={() => setConsent('granted')}>
          Allow
        </button>
      </div>
    </section>
  )
}

/** Reopens the banner; for the footer. */
export function CookieSettingsButton({ className }: { className?: string }) {
  if (!GA_ID) return null
  return (
    <button type="button" className={className} onClick={() => setConsent(null)}>
      Cookie settings
    </button>
  )
}
