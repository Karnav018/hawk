import { useCallback, useEffect, useRef, useState, useSyncExternalStore } from 'react'
import { track } from '../../analytics/ga'

type Options = { reducedMotion: boolean }

const getFilm = () => document.getElementById('film-video') as HTMLVideoElement | null

/** The first <source> whose media query matches, as the browser would pick. */
function preferredSource(): string {
  const video = getFilm()
  if (!video) return ''
  for (const source of video.querySelectorAll('source')) {
    if (!source.media || window.matchMedia(source.media).matches) return source.src
  }
  return ''
}

/**
 * Adopts the film <video> that index.html renders (so it starts loading before
 * any JavaScript runs): muted, looping, playing while on screen. The visitor
 * can turn sound on and pause it; a pause they ask for is respected (the film
 * is not restarted when it scrolls back into view or the tab regains focus).
 * Under reduced motion it never starts by itself.
 *
 * The browser picks a <source> once, at load. When the window changes
 * orientation this swaps to the matching file and carries the playhead over.
 */
export function useFilmPlayer({ reducedMotion }: Options) {
  // Start from what the prerendered HTML shows (paused, muted); the mirror
  // effect below reads the element's real state as soon as the page hydrates.
  const [paused, setPaused] = useState(true)
  const [muted, setMuted] = useState(true)
  const heldByVisitor = useRef(false)

  const src = useSyncExternalStore(
    (onChange) => {
      window.addEventListener('resize', onChange)
      return () => window.removeEventListener('resize', onChange)
    },
    preferredSource,
    // Prerendering has no <video> to ask; the browser's own pick stands.
    () => '',
  )

  const play = useCallback(() => {
    heldByVisitor.current = false
    getFilm()
      ?.play()
      .catch(() => {})
  }, [])

  const togglePlay = useCallback(() => {
    const video = getFilm()
    if (!video) return
    if (video.paused) {
      play()
    } else {
      heldByVisitor.current = true
      video.pause()
    }
  }, [play])

  // Asking for sound means asking to hear the film, so it also resumes.
  const toggleMute = useCallback(() => {
    const video = getFilm()
    if (!video) return
    video.muted = !video.muted
    track('film_sound', { on: !video.muted })
    if (!video.muted && video.paused) play()
  }, [play])

  // Orientation swaps keep the playhead and the play state. A window drag can
  // cross the breakpoint twice before the new file loads; by then the element
  // already reads as paused, so the first snapshot is kept until a load
  // actually completes. An empty currentSrc means the browser is still making
  // its own first pick, from the same media queries.
  const pendingResume = useRef<{ time: number; play: boolean } | null>(null)
  useEffect(() => {
    const video = getFilm()
    if (!video || !src || !video.currentSrc || video.currentSrc === src) return
    if (!pendingResume.current) {
      pendingResume.current = { time: video.currentTime, play: !video.paused }
    }
    video.src = src
    const resume = () => {
      const snapshot = pendingResume.current
      pendingResume.current = null
      if (!snapshot) return
      video.currentTime = snapshot.time
      if (snapshot.play) video.play().catch(() => {})
    }
    video.addEventListener('loadedmetadata', resume, { once: true })
    return () => video.removeEventListener('loadedmetadata', resume)
  }, [src])

  // Play while on screen. A page opened in a background tab refuses the first
  // play(); retry when it becomes visible, not only when the observer fires.
  useEffect(() => {
    const video = getFilm()
    if (!video) return
    if (reducedMotion) {
      if (!heldByVisitor.current) video.pause()
      return
    }
    let inView = false
    const tryPlay = () => {
      if (inView && !document.hidden && !heldByVisitor.current) video.play().catch(() => {})
    }
    const io = new IntersectionObserver(
      ([entry]) => {
        inView = entry.isIntersecting
        if (inView) tryPlay()
        else video.pause()
      },
      { threshold: 0.15 },
    )
    io.observe(video)
    document.addEventListener('visibilitychange', tryPlay)
    return () => {
      io.disconnect()
      document.removeEventListener('visibilitychange', tryPlay)
    }
  }, [reducedMotion])

  // Mirror the element's own state so the controls never drift from it.
  useEffect(() => {
    const video = getFilm()
    if (!video) return
    const sync = () => {
      setPaused(video.paused)
      setMuted(video.muted)
    }
    sync()
    const events = ['play', 'pause', 'volumechange'] as const
    events.forEach((e) => video.addEventListener(e, sync))
    return () => events.forEach((e) => video.removeEventListener(e, sync))
  }, [])

  return { paused, muted, togglePlay, toggleMute }
}
