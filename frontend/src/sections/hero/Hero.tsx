import type { MouseEvent } from 'react'
import { useMediaQuery } from '../../hooks/useMediaQuery'
import { PauseIcon, PlayIcon, SoundOffIcon, SoundOnIcon } from './icons'
import { useFilmPlayer } from './useFilmPlayer'
import styles from './Hero.module.css'

// The film itself is plain HTML (index.html) so it starts loading before this
// runs. The hero is a transparent frame over it: it holds the film's place in
// the page and carries the pause/sound pair. A click anywhere else on the
// film toggles sound.
export function Hero() {
  const reducedMotion = useMediaQuery('(prefers-reduced-motion: reduce)')
  const { paused, muted, togglePlay, toggleMute } = useFilmPlayer({ reducedMotion })

  const onFrameClick = (e: MouseEvent<HTMLElement>) => {
    if (e.target === e.currentTarget) toggleMute()
  }

  return (
    <section id="film" className={styles.hero} aria-label="Hawk launch film" onClick={onFrameClick}>
      {/* The page's title is the film's own end card; the film shows it. */}
      <h1 className="visually-hidden">Hawk — your second memory</h1>
      <div className={styles.controls}>
        <button
          type="button"
          className={styles.round}
          onClick={togglePlay}
          aria-label={paused ? 'Play film' : 'Pause film'}
        >
          {paused ? <PlayIcon /> : <PauseIcon />}
        </button>
        <button
          type="button"
          className={styles.round}
          onClick={toggleMute}
          aria-label="Sound"
          aria-pressed={!muted}
          data-hint={muted}
        >
          {muted ? <SoundOffIcon /> : <SoundOnIcon />}
        </button>
      </div>
    </section>
  )
}
