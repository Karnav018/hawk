import { CookieSettingsButton } from '../analytics/ConsentBanner'
import { track } from '../analytics/ga'
import { site } from '../site'
import { Logo } from './Logo'
import styles from './Footer.module.css'

// Wireframe 1b's closing bar: the logo on the left, the links on the right.
// The line beside the logo is the film's end card ("Hawk / Your second memory.").
// Shared with the legal pages, so its links work from any page.
export function Footer() {
  return (
    <footer className={styles.footer}>
      <div className={styles.bar}>
        <a href="/#film" className={styles.brand} aria-label={`${site.name}, back to the film`}>
          <Logo />
        </a>
        <p className={styles.tagline}>{site.tagline}.</p>
        <nav className={styles.links} aria-label="Footer">
          <a href={site.installUrl} className={styles.link}>
            Get the app
          </a>
          {site.legalLinks.map((link) => (
            <a key={link.label} href={link.href} className={styles.link}>
              {link.label}
            </a>
          ))}
          <a href={`mailto:${site.email}`} className={styles.link} onClick={() => track('contact_click')}>
            {site.email}
          </a>
          <CookieSettingsButton className={styles.link} />
        </nav>
        <p className={styles.legal}>
          © {new Date().getFullYear()} {site.name}
        </p>
      </div>
    </footer>
  )
}
