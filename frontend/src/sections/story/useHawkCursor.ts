import { useEffect, type RefObject } from 'react'

type Options = {
  section: RefObject<HTMLElement | null>
  cursor: RefObject<HTMLElement | null>
  enabled: boolean
}

/** The eye is 44px wide; the navbar's logo button it leaves from is 48px. */
const HOME_SCALE = 48 / 44

type Mode = 'docked' | 'launch' | 'follow' | 'return'

/**
 * The Hawk cursor for the story section.
 *
 * While the section is on screen and the mouse is over it, Hawk's eye
 * leaves the navbar's logo button (<html data-hawk-cursor="out"> empties the
 * button) and flies to the pointer, then follows it with a little lag,
 * looking the way it travels (--look-x / --look-y on the cursor). When the
 * mouse leaves the section (up onto the navbar, say) or the section scrolls
 * away, the eye flies home and the button fills again.
 *
 * Written straight to the DOM once per frame; the loop stops when the mark is
 * home.
 */
export function useHawkCursor({ section, cursor, enabled }: Options) {
  useEffect(() => {
    const sec = section.current
    const cur = cursor.current
    if (!enabled || !sec || !cur) return

    const pointer = { x: 0, y: 0 }
    const pos = { x: 0, y: 0, s: HOME_SCALE }
    const look = { x: 0, y: 0 }
    let mode: Mode = 'docked'
    let inView = false
    let inside = false
    let raf = 0

    const home = () => {
      const r = document.querySelector('[data-hawk-home]')?.getBoundingClientRect()
      return r && r.width ? { x: r.left + r.width / 2, y: r.top + r.height / 2 } : { x: innerWidth / 2, y: 40 }
    }

    const setOut = (out: boolean) => {
      if (out) document.documentElement.dataset.hawkCursor = 'out'
      else delete document.documentElement.dataset.hawkCursor
    }

    const tick = () => {
      raf = 0
      if (mode !== 'docked') {
        const target = mode === 'return' ? home() : pointer
        // A visible flight out of the navbar, a quicker one home, a light lag while following.
        const k = mode === 'launch' ? 0.085 : mode === 'return' ? 0.14 : 0.28
        const vx = (target.x - pos.x) * k
        const vy = (target.y - pos.y) * k
        pos.x += vx
        pos.y += vy
        // Looks where it is going: further the faster it moves, ahead at rest.
        const speed = Math.hypot(vx, vy)
        look.x += ((vx / (speed + 6)) - look.x) * 0.2
        look.y += ((vy / (speed + 6)) - look.y) * 0.2
        const dist = Math.hypot(target.x - pos.x, target.y - pos.y)
        if (mode === 'launch' && dist < 4) mode = 'follow'
        if (mode === 'return' && dist < 2) {
          mode = 'docked'
          setOut(false)
        }
      }

      // Shrinks from the button's size as it leaves, grows back as it docks.
      const scale = mode === 'return' || mode === 'docked' ? HOME_SCALE : 1
      pos.s += (scale - pos.s) * 0.2
      cur.style.transform = `translate3d(${pos.x}px, ${pos.y}px, 0) scale(${pos.s})`
      cur.style.setProperty('--look-x', look.x.toFixed(3))
      cur.style.setProperty('--look-y', look.y.toFixed(3))
      cur.style.opacity = mode === 'docked' ? '0' : '1'

      if (mode !== 'docked') raf = requestAnimationFrame(tick)
    }

    const schedule = () => {
      if (!raf) raf = requestAnimationFrame(tick)
    }

    const sync = () => {
      const want = inView && inside
      if (want && (mode === 'docked' || mode === 'return')) {
        if (mode === 'docked') {
          const h = home()
          pos.x = h.x
          pos.y = h.y
          pos.s = HOME_SCALE
        }
        mode = 'launch'
        setOut(true)
        sec.dataset.cursor = 'on'
      } else if (!want && (mode === 'launch' || mode === 'follow')) {
        mode = 'return'
        delete sec.dataset.cursor
      }
      schedule()
    }

    const onMove = (e: PointerEvent) => {
      if (e.pointerType !== 'mouse') return
      pointer.x = e.clientX
      pointer.y = e.clientY
      if (mode !== 'docked') schedule()
    }
    const onEnter = (e: PointerEvent) => {
      if (e.pointerType !== 'mouse') return
      inside = true
      sync()
    }
    const onLeave = (e: PointerEvent) => {
      if (e.pointerType !== 'mouse') return
      inside = false
      sync()
    }

    const io = new IntersectionObserver(
      ([entry]) => {
        inView = entry.isIntersecting
        // Scrolling brings the section under a mouse that has not moved, so
        // no pointerenter fires; check where the pointer already is.
        if (inView && !inside) {
          const el = document.elementFromPoint(pointer.x, pointer.y)
          inside = !!el && sec.contains(el)
        }
        sync()
      },
      { threshold: 0.3 },
    )

    window.addEventListener('pointermove', onMove, { passive: true })
    sec.addEventListener('pointerenter', onEnter)
    sec.addEventListener('pointerleave', onLeave)
    io.observe(sec)

    return () => {
      cancelAnimationFrame(raf)
      io.disconnect()
      window.removeEventListener('pointermove', onMove)
      sec.removeEventListener('pointerenter', onEnter)
      sec.removeEventListener('pointerleave', onLeave)
      setOut(false)
      delete sec.dataset.cursor
      cur.style.opacity = '0'
    }
  }, [section, cursor, enabled])
}
