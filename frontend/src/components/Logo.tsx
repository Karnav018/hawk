import styles from './Logo.module.css'

type Props = { size?: number }
type MarkProps = Props & { tone?: 'ink' | 'paper' }

// Hawk v3 mark: disc r24 @ (32,32), highlight r7 @ (24,24) on a 64 grid. The
// highlight sits upper-left and never rotates. `tone` is the surface it sits
// on: a cream disc on the navy page, a navy disc on a cream button.
export function LogoMark({ size = 28, tone = 'ink' }: MarkProps) {
  return (
    <svg
      className={styles.mark}
      width={size}
      height={size}
      viewBox="0 0 64 64"
      fill="none"
      aria-hidden="true"
    >
      <circle cx="32" cy="32" r="24" fill={tone === 'ink' ? 'var(--paper)' : 'var(--paper-ink)'} />
      <circle cx="24" cy="24" r="7" fill="var(--accent)" />
    </svg>
  )
}

// Sized by --logo (the mark's diameter) set on any ancestor; the wordmark
// scales with it. Defaults to 28px.
export function Logo() {
  return (
    <span className={styles.lockup}>
      <LogoMark />
      <span className={styles.wordmark}>Hawk</span>
    </span>
  )
}
