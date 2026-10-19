import { useEffect, useRef, type CSSProperties, type PointerEvent, type ReactNode } from 'react'
import { track } from '../../analytics/ga'
import { HawkEye } from '../../components/HawkEye'
import { useMediaQuery } from '../../hooks/useMediaQuery'
import { useInViewOnce } from '../../hooks/useScroll'
import { Bubble, Orbit, Polaroid, Sparkle, StressedFigure, VoiceNote } from './doodles'
import styles from './Pain.module.css'

/*
 * The pain section: a paper collage on the night sky. Cream blobs, a huge
 * extruded headline, the stressed doodle and the things it lost on one side,
 * Hawk's eye in its orbit on the other.
 *
 * Every element is two boxes. The outer one (.layer) is placed on the canvas
 * and drifts with the pointer by its depth (--d), so the collage has depth.
 * The inner one (.piece) arrives when the section first comes into view
 * (blobs pop, paper is tossed down, lines draw themselves) and then idles.
 */

type LayerProps = {
  at: string
  depth: number
  delay: number
  enter?: 'pop' | 'toss' | 'rise'
  children: ReactNode
}

function Layer({ at, depth, delay, enter = 'pop', children }: LayerProps) {
  return (
    <div className={`${styles.layer} ${styles[at]}`} style={{ '--d': depth } as CSSProperties}>
      <div className={styles.piece} data-enter={enter} style={{ '--delay': `${delay}ms` } as CSSProperties}>
        {children}
      </div>
    </div>
  )
}

export function Pain() {
  const reducedMotion = useMediaQuery('(prefers-reduced-motion: reduce)')
  const [ref, seen] = useInViewOnce<HTMLElement>(0.3)
  useEffect(() => {
    if (seen) track('section_view', { section: 'pain' })
  }, [seen])
  const eyeRef = useRef<SVGSVGElement>(null)
  const frame = useRef(0)

  // Pointer depth and the eye's gaze, written straight to the DOM once per frame.
  const onPointerMove = (e: PointerEvent<HTMLElement>) => {
    if (e.pointerType !== 'mouse' || reducedMotion) return
    const section = e.currentTarget
    const { clientX, clientY } = e
    cancelAnimationFrame(frame.current)
    frame.current = requestAnimationFrame(() => {
      const r = section.getBoundingClientRect()
      section.style.setProperty('--px', (((clientX - r.left) / r.width) * 2 - 1).toFixed(3))
      section.style.setProperty('--py', (((clientY - r.top) / r.height) * 2 - 1).toFixed(3))
      const eye = eyeRef.current
      if (!eye) return
      const b = eye.getBoundingClientRect()
      const dx = clientX - (b.left + b.width / 2)
      const dy = clientY - (b.top + b.height / 2)
      const reach = Math.max(1, Math.hypot(dx, dy) / 260)
      eye.style.setProperty('--look-x', (dx / 260 / reach).toFixed(3))
      eye.style.setProperty('--look-y', (dy / 260 / reach).toFixed(3))
    })
  }

  const onPointerLeave = (e: PointerEvent<HTMLElement>) => {
    e.currentTarget.style.setProperty('--px', '0')
    e.currentTarget.style.setProperty('--py', '0')
    // Back to its resting gaze (set in CSS).
    eyeRef.current?.style.removeProperty('--look-x')
    eyeRef.current?.style.removeProperty('--look-y')
  }

  return (
    <section
      id="pain"
      ref={ref}
      className={styles.pain}
      data-seen={seen || reducedMotion}
      aria-labelledby="pain-title"
      onPointerMove={onPointerMove}
      onPointerLeave={onPointerLeave}
    >
      {/* Paper blobs */}
      <Layer at="posBlobLeft" depth={5} delay={0}>
        <div className={styles.blob} />
      </Layer>
      <Layer at="posBlobEye" depth={7} delay={90}>
        <div className={styles.blob} />
      </Layer>
      <Layer at="posBlobFigure" depth={5} delay={160}>
        <div className={styles.blob} />
      </Layer>
      <Layer at="posBlobRight" depth={4} delay={230}>
        <div className={styles.blob} />
      </Layer>

      {/* The lost side */}
      <Layer at="posBubble" depth={12} delay={420} enter="rise">
        <Bubble className={styles.bubble}>forgot what was said</Bubble>
      </Layer>
      <Layer at="posFigure" depth={9} delay={380} enter="rise">
        <StressedFigure className={styles.figure} />
      </Layer>
      <Layer at="posPolaroid" depth={18} delay={620} enter="toss">
        <Polaroid className={styles.polaroid} />
      </Layer>
      <Layer at="posVoice" depth={22} delay={720} enter="toss">
        <VoiceNote className={styles.voice} />
      </Layer>
      <Layer at="posTagImg" depth={26} delay={820} enter="toss">
        <span className={styles.tag}>IMG_4829.jpg</span>
      </Layer>
      <Layer at="posTagDoc" depth={24} delay={900} enter="toss">
        <span className={styles.tag}>final_v3_REAL.docx</span>
      </Layer>

      {/* Hawk's side */}
      <Layer at="posGlow" depth={10} delay={520}>
        <span className={styles.glow} />
      </Layer>
      <Layer at="posOrbit" depth={12} delay={640}>
        <Orbit className={styles.orbit} moving={!reducedMotion} />
      </Layer>
      <Layer at="posEye" depth={14} delay={560}>
        <HawkEye ref={eyeRef} className={styles.eye} open={seen || reducedMotion} blink={!reducedMotion} />
      </Layer>
      <Layer at="posSays" depth={11} delay={1000} enter="rise">
        <span className={styles.says}>just tell me what you remember</span>
      </Layer>

      {/* Sparkles */}
      <Layer at="posSparkEye" depth={16} delay={1100}>
        <Sparkle className={styles.spark} />
      </Layer>
      <Layer at="posSparkFigure" depth={14} delay={1150}>
        <Sparkle className={styles.spark} style={{ animationDelay: '-1.2s' }} />
      </Layer>
      <Layer at="posSparkRight" depth={8} delay={1200}>
        <Sparkle className={styles.spark} style={{ animationDelay: '-2.1s' }} />
      </Layer>

      {/* The line */}
      <div className={styles.copy}>
        <h2 id="pain-title" className={styles.title}>
          <span className={styles.titleLine} style={{ '--delay': '200ms' } as CSSProperties}>
            You remember
          </span>{' '}
          <span className={styles.titleLine} style={{ '--delay': '320ms' } as CSSProperties}>
            the moment.
          </span>
        </h2>
        <p className={styles.sub}>
          Not <em>where</em> you put it.
        </p>
      </div>
    </section>
  )
}
