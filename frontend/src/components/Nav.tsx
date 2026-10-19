import { onInstallClick, useInstallHref } from '../install/install'
import { useActiveSection, useScrolledPast } from '../hooks/useScroll'
import { site } from '../site'
import { Logo, LogoMark } from './Logo'
import styles from './Nav.module.css'

// `wide`: only where there is room; the logo button already goes to the film.
const LINKS = [
  { id: 'film', label: 'Film', wide: true },
  { id: 'pain', label: 'Why Hawk' },
  { id: 'story', label: 'Story' },
] as const

const SECTION_IDS = LINKS.map((l) => l.id)

/** Past this, the pill navbar is showing (and the floating install steps aside). */
export const NAV_REVEAL_PX = 80

// Over the film only the wordmark floats, so nothing covers it. Once the
// visitor scrolls, a floating pill drops in: logo button, section links, and
// the install button.
export function Nav() {
  const open = useScrolledPast(NAV_REVEAL_PX)
  const active = useActiveSection(SECTION_IDS)
  const installHref = useInstallHref()

  return (
    <header className={styles.nav} data-open={open}>
      <a href="#film" className={styles.brand} aria-label={`${site.name}, back to the film`} inert={open}>
        <Logo />
      </a>

      <nav className={styles.pill} aria-label="Main" inert={!open}>
        {/* data-hawk-home: where the story section's cursor leaves from and returns to. */}
        <a href="#film" className={styles.home} aria-label={`${site.name}, back to the film`} data-hawk-home>
          <LogoMark size={26} tone="paper" />
        </a>
        <div className={styles.links}>
          {LINKS.map((link) => (
            <a
              key={link.id}
              href={`#${link.id}`}
              className={styles.link}
              data-wide={'wide' in link || undefined}
              aria-current={active === link.id ? 'true' : undefined}
            >
              {link.label}
            </a>
          ))}
        </div>
        <a href={installHref} className={styles.cta} onClick={(e) => onInstallClick(e, 'nav')}>
          Install<span className={styles.ctaLong}>&nbsp;app</span>
        </a>
      </nav>
    </header>
  )
}
