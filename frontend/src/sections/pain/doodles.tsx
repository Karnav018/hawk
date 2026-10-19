import type { CSSProperties, ReactNode } from 'react'
import styles from './Pain.module.css'

/*
 * Pieces for the pain collage. Line art uses pathLength="1" so CSS can draw it
 * on with stroke-dashoffset; inside a figure the strokes draw one after
 * another (--i), which reads as someone sketching.
 */

type Stroke = { d: string; tone?: 'accent' }

function Strokes({ strokes }: { strokes: Stroke[] }) {
  return strokes.map((s, i) => (
    <path
      key={i}
      d={s.d}
      pathLength={1}
      className={styles.stroke}
      data-tone={s.tone}
      style={{ '--i': i } as CSSProperties}
    />
  ))
}

// Frazzled hair, worried brows, wobbly mouth, a squiggle of worry, sweat.
const STRESSED: Stroke[] = [
  { d: 'M80 34 C96 34 107 46 107 61 C107 77 95 88 80 88 C64 88 53 76 53 61 C53 46 64 34 80 34' },
  { d: 'M57 47 L61 34 L68 44 L73 30 L79 42 L85 29 L90 42 L96 32 L102 46' },
  { d: 'M65 52 L76 57 M95 52 L84 57' },
  { d: 'M68 63 a3.4 3.4 0 1 0 6.8 0 a3.4 3.4 0 1 0 -6.8 0 M85 63 a3.4 3.4 0 1 0 6.8 0 a3.4 3.4 0 1 0 -6.8 0' },
  { d: 'M67 77 q3.5 -5 7 0 t7 0 t7 0 t7 0' },
  { d: 'M80 88 L80 172' },
  { d: 'M80 172 L64 236 M80 172 L97 236' },
  { d: 'M44 14 q7 -7 14 0 t14 0 t14 0 t14 0 t14 0', tone: 'accent' },
  { d: 'M117 50 q5 8 0 11 q-5 -3 0 -11 M41 78 q4 7 0 9 q-4 -2 0 -9', tone: 'accent' },
]

export function StressedFigure({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 160 240" fill="none" aria-hidden="true">
      <Strokes strokes={STRESSED} />
    </svg>
  )
}

// A wobbly hand-drawn speech bubble, tail bottom-left.
const BUBBLE =
  'M30 14 C80 4 160 6 196 18 C214 26 216 70 200 84 C170 100 110 98 70 96 L40 116 L48 92 C20 88 8 70 10 48 C12 28 18 18 30 14'

export function Bubble({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <div className={className}>
      <svg className={styles.bubbleShape} viewBox="0 0 220 120" fill="none" aria-hidden="true">
        <Strokes strokes={[{ d: BUBBLE }]} />
      </svg>
      <span className={styles.bubbleText}>{children}</span>
    </div>
  )
}

export function Sparkle({ className, style }: { className?: string; style?: CSSProperties }) {
  return (
    <svg className={className} style={style} viewBox="0 0 24 24" aria-hidden="true">
      <path d="M12 0 C13 8 16 11 24 12 C16 13 13 16 12 24 C11 16 8 13 0 12 C8 11 11 8 12 0 Z" />
    </svg>
  )
}

/** A dashed orbit around the eye, with a paper card travelling it. */
export function Orbit({ className, moving }: { className?: string; moving: boolean }) {
  const path = 'M10 60 C10 30 90 12 200 12 C310 12 390 30 390 60 C390 90 310 108 200 108 C90 108 10 90 10 60 Z'
  return (
    <svg className={className} viewBox="0 0 400 120" fill="none" aria-hidden="true">
      <path className={styles.orbitPath} d={path} pathLength={1} />
      <g transform={moving ? undefined : 'translate(390 60)'}>
        <rect x="-11" y="-8" width="22" height="16" rx="2" fill="var(--paper-card)" stroke="#0c1017" strokeWidth="1.5" />
        {moving && <animateMotion dur="14s" repeatCount="indefinite" rotate="auto" path={path} />}
      </g>
    </svg>
  )
}

export function Polaroid({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 170 190" aria-hidden="true">
      <rect x="4" y="4" width="162" height="182" rx="7" fill="var(--paper)" stroke="var(--paper-ink)" strokeWidth="4" />
      <rect x="20" y="20" width="130" height="118" rx="3" fill="none" stroke="var(--paper-ink)" strokeWidth="3.5" />
      <path
        d="M22 126 C42 90 60 88 78 112 C92 96 108 84 124 94 C134 100 142 110 148 118"
        fill="none"
        stroke="var(--paper-ink)"
        strokeWidth="3.5"
        strokeLinecap="round"
      />
      <circle cx="122" cy="46" r="10" fill="none" stroke="var(--paper-ink)" strokeWidth="3.5" />
      <path d="M26 160 L92 154" stroke="#8a8f9c" strokeWidth="6" strokeLinecap="round" />
    </svg>
  )
}

const BARS = [14, 26, 18, 34, 22, 40, 26, 34, 18, 28, 14]

export function VoiceNote({ className }: { className?: string }) {
  return (
    <div className={className} aria-hidden="true">
      <span className={styles.voiceDot} />
      <span className={styles.voiceBars}>
        {BARS.map((h, i) => (
          <span key={i} style={{ '--h': h, '--i': i } as CSSProperties} />
        ))}
      </span>
    </div>
  )
}
