import { StrictMode } from 'react'
import { createRoot, hydrateRoot } from 'react-dom/client'
// Self-hosted (no third-party round trips). Only the faces above the fold load
// with the page: the film's first frames get the bandwidth first.
import '@fontsource/archivo/latin-400.css'
import '@fontsource/archivo/latin-600.css'
import '@fontsource/archivo/latin-800.css'
import './index.css'
import { bootAnalytics } from './analytics/ga'
import { listenForInstallPrompt } from './install/install'
import App from './App.tsx'

// The serif and mono faces are only used below the film. Fetch them once the
// film is playing or the visitor starts scrolling, whichever comes first; the
// timer covers reduced motion, where the film never starts by itself.
let laterFontsRequested = false
function loadLaterFonts() {
  if (laterFontsRequested) return
  laterFontsRequested = true
  void import('./fonts-later.ts')
}
document.getElementById('film-video')?.addEventListener('playing', loadLaterFonts, { once: true })
window.addEventListener('scroll', loadLaterFonts, { once: true, passive: true })
window.setTimeout(loadLaterFonts, 2500)

listenForInstallPrompt()

const root = document.getElementById('root')!
const app = (
  <StrictMode>
    <App />
  </StrictMode>
)
// Built pages arrive prerendered (scripts/prerender.mjs): React adopts that
// HTML instead of drawing it again. The dev server's pages start empty.
if (root.hasChildNodes()) hydrateRoot(root, app)
else createRoot(root).render(app)

bootAnalytics()
