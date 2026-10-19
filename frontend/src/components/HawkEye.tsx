import { useId, type Ref } from 'react'
import styles from './HawkEye.module.css'

/*
 * Hawk's eye: the same eye as the app and the launch film, cut from the
 * film's paper (design/blender/film/puppets.py `build_eye`, whose shapes are
 * the app's EyeOrb at rest). Drawn in the film's own units, centred on 0,0:
 * the eye is 1 across and 0.74 tall per side.
 *
 *  - `open`: shut until true, then it opens with a little overshoot
 *    (--open-delay sets when);
 *  - `blink`: double-blinks every six seconds, like the app's READY state;
 *  - the disc looks along --look-x / --look-y (-1..1), set by whoever
 *    places the eye (they inherit, so any ancestor will do).
 */
const INK = '#0e1522'
const CREAM = '#efe6d3'
const BLUE = '#59d3ff'
const SHEEN = '#9fcdf0'

/** The eye's shape, (|x|/a)^n + (|y|/b)^n = 1, as a path. */
function superellipse(a: number, b: number, n = 2.5, steps = 96) {
  let d = ''
  for (let i = 0; i < steps; i++) {
    const t = (2 * Math.PI * i) / steps
    const c = Math.cos(t)
    const s = Math.sin(t)
    const x = a * Math.sign(c) * Math.abs(c) ** (2 / n)
    const y = b * Math.sign(s) * Math.abs(s) ** (2 / n)
    d += `${i ? 'L' : 'M'}${x.toFixed(4)} ${y.toFixed(4)}`
  }
  return `${d}Z`
}

/** The shut lid: a strip sagging in the middle, thickest there. */
function closedLid(half: number, steps = 40) {
  const top: string[] = []
  const bottom: string[] = []
  for (let i = 0; i <= steps; i++) {
    const x = -half + (2 * half * i) / steps
    const u = x / half
    const sag = 0.1 * (1 - u * u)
    const th = 0.13 * Math.sqrt(Math.max(0, 1 - u * u)) + 0.025
    top.push(`${x.toFixed(4)} ${(sag - th / 2).toFixed(4)}`)
    bottom.push(`${x.toFixed(4)} ${(sag + th / 2).toFixed(4)}`)
  }
  return `M${top.join('L')}L${bottom.reverse().join('L')}Z`
}

const EYE = {
  ring: superellipse(1.17, 0.91),
  gap: superellipse(1.075, 0.815),
  sclera: superellipse(1, 0.74),
  lid: closedLid(1.14),
}

// The paper's cut edge, faint, so cream still reads on a cream page.
const EDGE = { stroke: INK, strokeOpacity: 0.3, strokeWidth: 0.02 }

type Props = {
  ref?: Ref<SVGSVGElement>
  className?: string
  open?: boolean
  blink?: boolean
}

export function HawkEye({ ref, className, open = true, blink = false }: Props) {
  const clip = useId()
  return (
    <svg
      ref={ref}
      className={className ? `${styles.eye} ${className}` : styles.eye}
      viewBox="-1.2 -0.9 2.4 1.8"
      data-open={open}
      data-blink={blink || undefined}
      aria-hidden="true"
    >
      <defs>
        <clipPath id={clip}>
          <path d={EYE.sclera} />
        </clipPath>
      </defs>
      <g className={styles.open}>
        <g className={styles.blink}>
          <path d={EYE.ring} fill={CREAM} {...EDGE} />
          <path d={EYE.gap} fill={INK} />
          <path d={EYE.sclera} fill={CREAM} />
          <g clipPath={`url(#${clip})`}>
            <g className={styles.gaze}>
              <circle r="0.4" fill={BLUE} />
              <ellipse rx="0.22" ry="0.11" transform="translate(-0.13 -0.12) rotate(-40)" fill={SHEEN} />
              <circle r="0.19" fill={INK} />
              <circle cx="-0.14" cy="-0.14" r="0.085" fill={CREAM} />
            </g>
          </g>
        </g>
      </g>
      {/* Shown while the eye is shut: before it opens, and mid-blink. */}
      <path className={styles.shut} d={EYE.lid} fill={CREAM} {...EDGE} />
      <path className={styles.blinkShut} d={EYE.lid} fill={CREAM} {...EDGE} />
    </svg>
  )
}
