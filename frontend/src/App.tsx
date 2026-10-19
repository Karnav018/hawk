import { useEffect } from 'react'
import { ConsentBanner } from './analytics/ConsentBanner'
import { Footer } from './components/Footer'
import { InstallFab } from './components/InstallFab'
import { Nav } from './components/Nav'
import { Hero } from './sections/hero/Hero'
import { Pain } from './sections/pain/Pain'
import { Story } from './sections/story/Story'

// Landing page, wireframe 1b ("video-first"): hero → pain → hawk story →
// core features → footer. Built so far: the film, the pain scene, the story,
// the footer.
export default function App() {
  // The sections are rendered by React, after the browser has already tried
  // to jump to a link's #hash; honour it once they exist.
  useEffect(() => {
    const id = decodeURIComponent(window.location.hash.slice(1))
    if (id) document.getElementById(id)?.scrollIntoView({ behavior: 'instant' })
  }, [])

  return (
    <>
      <Nav />
      <main>
        <Hero />
        <Pain />
        <Story />
      </main>
      <Footer />
      <InstallFab />
      <ConsentBanner afterFilm />
    </>
  )
}
