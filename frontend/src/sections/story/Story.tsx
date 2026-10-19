import { useEffect, useRef, type CSSProperties } from 'react'
import { track } from '../../analytics/ga'
import { createPortal } from 'react-dom'
import { HawkEye } from '../../components/HawkEye'
import { useMediaQuery } from '../../hooks/useMediaQuery'
import { useInViewOnce, useViewProgress } from '../../hooks/useScroll'
import { useHawkCursor } from './useHawkCursor'
import styles from './Story.module.css'

/*
 * The story: why it is called Hawk, on a plain dark blue page. The words are
 * the film's ("A hawk sees what is almost invisible, from far away").
 *
 * Motion:
 *  - arriving, the words rise in one after another;
 *  - with a mouse, Hawk's eye leaves the navbar's logo button and becomes
 *    the cursor while you are here (useHawkCursor), then flies home.
 */
const STORY: { text: string; key?: boolean }[] = [
  { text: 'A hawk sees what is' },
  { text: 'almost invisible,', key: true },
  { text: 'from far away. It never digs through the whole field. It spots the one thing that matters and goes' },
  { text: 'straight to it.', key: true },
  { text: 'Hawk does the same for everything you’ve saved,' },
  { text: 'without moving a single file.', key: true },
]

const WORDS = STORY.flatMap((part) => part.text.split(' ').map((word) => ({ word, key: part.key })))

export function Story() {
  const reducedMotion = useMediaQuery('(prefers-reduced-motion: reduce)')
  const mouse = useMediaQuery('(hover: hover) and (pointer: fine)')
  const [sectionRef, seen] = useInViewOnce<HTMLElement>(0.25)
  useEffect(() => {
    if (seen) track('section_view', { section: 'story' })
  }, [seen])
  const cursorRef = useRef<HTMLDivElement>(null)
  // On the whole text block, so the sign-off below the paragraph can use it too.
  const copyRef = useRef<HTMLDivElement>(null)
  useViewProgress(copyRef, reducedMotion)
  const hawkCursor = mouse && !reducedMotion
  useHawkCursor({ section: sectionRef, cursor: cursorRef, enabled: hawkCursor })

  return (
    <section
      id="story"
      ref={sectionRef}
      className={styles.story}
      data-seen={seen || reducedMotion}
      aria-labelledby="story-title"
    >
      {/* Rises over the collage above, so its blobs sink behind a soft edge. */}
      <svg className={styles.seam} viewBox="0 0 1440 100" preserveAspectRatio="none" aria-hidden="true">
        <path
          d="M0 34 C180 8 360 26 520 56 C680 84 900 82 1100 52 C1250 28 1360 18 1440 28 L1440 100 L0 100 Z"
          fill="var(--story-bg)"
        />
      </svg>

      <div ref={copyRef} className={styles.copy}>
        {/* No visible title; screen readers still get one for the section. */}
        <h2 id="story-title" className="visually-hidden">
          Why a hawk
        </h2>
        <p className={styles.text}>
          {WORDS.map((w, i) => (
            <span key={i}>
              <span className={styles.word} data-key={w.key || undefined} style={{ '--i': i } as CSSProperties}>
                {w.word}
              </span>{' '}
            </span>
          ))}
        </p>
        <p className={styles.sign}>— that’s why we called it Hawk.</p>
      </div>

      {hawkCursor &&
        createPortal(
          <div ref={cursorRef} className={styles.cursor} aria-hidden="true">
            <HawkEye />
          </div>,
          document.body,
        )}
    </section>
  )
}
