import { onInstallClick, useInstallHref } from '../install/install'
import { useScrolledPast } from '../hooks/useScroll'
import { ButtonLink } from './ButtonLink'
import { LogoMark } from './Logo'
import { NAV_REVEAL_PX } from './Nav'
import styles from './InstallFab.module.css'

// Bottom-right over the film. Once the pill navbar drops in it carries the
// install button, so this one steps aside: one install button on screen at a time.
export function InstallFab() {
  const navOpen = useScrolledPast(NAV_REVEAL_PX)
  const installHref = useInstallHref()

  return (
    <div className={styles.fab} data-hidden={navOpen} inert={navOpen}>
      <ButtonLink
        href={installHref}
        className={styles.button}
        onClick={(e) => onInstallClick(e, 'fab')}
      >
        <LogoMark size={22} tone="paper" />
        Install app
      </ButtonLink>
    </div>
  )
}
