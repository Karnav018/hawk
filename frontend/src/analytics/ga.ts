import { getConsent, subscribeConsent } from './consent'

/*
 * Google Analytics 4, loaded only after the visitor allows it ("basic" consent
 * mode): before that, nothing is requested from Google and no cookie is set.
 * The measurement ID comes from the VITE_GA_MEASUREMENT_ID environment
 * variable at build time; without it there is no analytics and no banner.
 */
export const GA_ID: string = import.meta.env.VITE_GA_MEASUREMENT_ID ?? ''

declare global {
  interface Window {
    dataLayer?: unknown[]
    gtag?: (...args: unknown[]) => void
  }
}

let started = false

function start() {
  if (started || !GA_ID) return
  started = true
  window.dataLayer = window.dataLayer ?? []
  window.gtag = function gtag() {
    // gtag.js reads Arguments objects from the data layer, not arrays.
    // oxlint-disable-next-line prefer-rest-params
    window.dataLayer!.push(arguments)
  }
  window.gtag('js', new Date())
  window.gtag('consent', 'default', {
    analytics_storage: 'granted',
    ad_storage: 'denied',
    ad_user_data: 'denied',
    ad_personalization: 'denied',
  })
  window.gtag('config', GA_ID, { allow_google_signals: false, allow_ad_personalization_signals: false })
  const script = document.createElement('script')
  script.async = true
  script.src = `https://www.googletagmanager.com/gtag/js?id=${encodeURIComponent(GA_ID)}`
  document.head.append(script)
}

function stop() {
  if (started) window.gtag?.('consent', 'update', { analytics_storage: 'denied' })
  // Remove the cookies it set, on this host and on the bare domain.
  const domain = location.hostname.replace(/^www\./, '')
  for (const cookie of document.cookie.split('; ')) {
    const name = cookie.split('=')[0]
    if (!name.startsWith('_ga')) continue
    for (const scope of ['', `; domain=.${domain}`]) document.cookie = `${name}=; Max-Age=0; path=/${scope}`
  }
}

/** Call once per page. Starts analytics now or later, as the visitor chooses. */
export function bootAnalytics() {
  if (!GA_ID) return
  subscribeConsent(() => {
    const consent = getConsent()
    if (consent === 'granted') start()
    else if (consent === 'denied') stop()
  })
  // Returning visitors who allowed it: load once the page is idle, so the
  // film and fonts get the bandwidth first.
  if (getConsent() === 'granted') {
    if ('requestIdleCallback' in window) requestIdleCallback(start, { timeout: 4000 })
    else setTimeout(start, 2000)
  }
}

type Params = Record<string, string | number | boolean>

/** A GA4 event. Does nothing unless the visitor allowed analytics. */
export function track(event: string, params?: Params) {
  if (started && getConsent() === 'granted') window.gtag?.('event', event, params)
}
