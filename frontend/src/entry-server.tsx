/* oxlint-disable react/only-export-components -- a build-time entry, never hot-reloaded */
import { StrictMode, type ReactNode } from 'react'
import { renderToString } from 'react-dom/server'
import App from './App'
import { InstallPage } from './install/InstallPage'
import { DeleteAccountPage } from './legal/DeleteAccountPage'
import { PrivacyPage } from './legal/PrivacyPage'
import { TermsPage } from './legal/TermsPage'
import { PAGES, type PageId } from './seo/pages'

/*
 * The prerender build (scripts/prerender.mjs): every page's view as HTML, so
 * search engines and link previews get the whole page without running
 * JavaScript. The browser then hydrates it (main.tsx, legal/mount.tsx).
 */
const VIEWS: Record<PageId, () => ReactNode> = {
  home: () => <App />,
  install: () => <InstallPage />,
  privacy: () => <PrivacyPage />,
  terms: () => <TermsPage />,
  'delete-account': () => <DeleteAccountPage />,
}

export function render(id: PageId): string {
  return renderToString(<StrictMode>{VIEWS[id]()}</StrictMode>)
}

export { PAGES }
