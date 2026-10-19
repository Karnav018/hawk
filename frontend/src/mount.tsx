import { StrictMode, type ReactNode } from 'react'
import { createRoot, hydrateRoot } from 'react-dom/client'
import { bootAnalytics } from './analytics/ga'
import { listenForInstallPrompt } from './install/install'
// The pages besides the landing (legal, install) are mostly text, so every
// face they use loads with them.
import '@fontsource/archivo/latin-400.css'
import '@fontsource/archivo/latin-600.css'
import '@fontsource/archivo/latin-800.css'
import '@fontsource/instrument-serif/latin-400.css'
import '@fontsource/instrument-serif/latin-400-italic.css'
import './index.css'

export function mount(page: ReactNode) {
  const root = document.getElementById('root')!
  const app = <StrictMode>{page}</StrictMode>
  listenForInstallPrompt()
  // Prerendered in the build (scripts/prerender.mjs); empty in dev.
  if (root.hasChildNodes()) hydrateRoot(root, app)
  else createRoot(root).render(app)
  bootAnalytics()
}
