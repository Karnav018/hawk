import { useEffect, useRef, useState, useSyncExternalStore, type RefObject } from 'react'

/** True once the page is scrolled past `px`. Re-renders only when that flips. */
export function useScrolledPast(px: number): boolean {
  return useSyncExternalStore(
    (onChange) => {
      window.addEventListener('scroll', onChange, { passive: true })
      return () => window.removeEventListener('scroll', onChange)
    },
    () => window.scrollY > px,
    () => false,
  )
}

/** The id of the section that fills most of the viewport's middle band. */
export function useActiveSection(ids: readonly string[]): string | null {
  const [active, setActive] = useState<string | null>(null)
  useEffect(() => {
    const io = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) if (entry.isIntersecting) setActive(entry.target.id)
      },
      // A thin band across the middle of the screen: whichever section
      // crosses it is the one being read.
      { rootMargin: '-45% 0px -45% 0px' },
    )
    for (const id of ids) {
      const el = document.getElementById(id)
      if (el) io.observe(el)
    }
    return () => io.disconnect()
  }, [ids])
  return active
}

/** Becomes true the first time the element is `threshold` visible, then stays. */
export function useInViewOnce<T extends Element>(threshold = 0.25) {
  const ref = useRef<T>(null)
  const [seen, setSeen] = useState(false)
  useEffect(() => {
    const el = ref.current
    if (!el || seen) return
    const io = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setSeen(true)
          io.disconnect()
        }
      },
      { threshold },
    )
    io.observe(el)
    return () => io.disconnect()
  }, [seen, threshold])
  return [ref, seen] as const
}

/**
 * Writes how far `ref` has travelled up the screen as --r on it (0 when its
 * top reaches `start` of the viewport height, 1 when its bottom reaches
 * `end`), once per frame and only while it is near the screen. `frozen` pins
 * it at 1. No re-renders.
 */
export function useViewProgress(
  ref: RefObject<HTMLElement | null>,
  frozen: boolean,
  start = 0.9,
  end = 0.75,
) {
  useEffect(() => {
    const el = ref.current
    if (!el) return
    if (frozen) {
      el.style.setProperty('--r', '1')
      return
    }
    let raf = 0
    const update = () => {
      raf = 0
      const r = el.getBoundingClientRect()
      const vh = window.innerHeight
      const p = (start * vh - r.top) / (r.height + (start - end) * vh)
      el.style.setProperty('--r', Math.min(1, Math.max(0, p)).toFixed(4))
    }
    const schedule = () => {
      if (!raf) raf = requestAnimationFrame(update)
    }
    const io = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          window.addEventListener('scroll', schedule, { passive: true })
          window.addEventListener('resize', schedule)
          schedule()
        } else {
          window.removeEventListener('scroll', schedule)
          window.removeEventListener('resize', schedule)
        }
      },
      { rootMargin: '25% 0px' },
    )
    update()
    io.observe(el)
    return () => {
      io.disconnect()
      cancelAnimationFrame(raf)
      window.removeEventListener('scroll', schedule)
      window.removeEventListener('resize', schedule)
    }
  }, [ref, frozen, start, end])
}
