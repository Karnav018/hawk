import { site } from '../site.ts'
import { PAGES, SHARE_IMAGE, url, type Page } from './pages.ts'
import type { Stores } from './stores.ts'

/** Search-console ownership tags, from the build environment (both optional). */
export type Verification = { google?: string; bing?: string }

const attr = (value: string) =>
  value.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')

// JSON inside <script>: a "</script>" in any string must not end the tag.
const json = (value: unknown) => JSON.stringify(value).replaceAll('<', '\\u003c')

const meta = (key: 'name' | 'property', name: string, content: string | number) =>
  `<meta ${key}="${name}" content="${attr(String(content))}" />`

/** The <head> tags for one page: search, link previews, app stores, icons, structured data. */
export function renderHead(page: Page, stores: Stores, verification: Verification = {}): string {
  const canonical = url(page.path)
  const share = page.shareDescription ?? page.description
  const { android, ios } = stores

  return [
    `<title>${attr(page.title)}</title>`,
    meta('name', 'description', page.description),
    `<link rel="canonical" href="${canonical}" />`,
    meta('name', 'robots', 'index, follow, max-image-preview:large, max-snippet:-1'),
    meta('name', 'application-name', site.name),
    meta('name', 'apple-mobile-web-app-title', site.name),
    meta('name', 'theme-color', page.themeColor),
    `<link rel="icon" type="image/svg+xml" href="/favicon.svg" />`,
    `<link rel="apple-touch-icon" href="/apple-touch-icon.png" />`,
    `<link rel="manifest" href="/site.webmanifest" />`,
    verification.google && meta('name', 'google-site-verification', verification.google),
    verification.bing && meta('name', 'msvalidate.01', verification.bing),
    // Safari on iPhone shows its own "Open / Get" banner for the app.
    ios.live && ios.id && meta('name', 'apple-itunes-app', `app-id=${ios.id}`),
    // Link previews (WhatsApp, iMessage, X, LinkedIn, Slack...). Absolute
    // URLs: crawlers don't resolve relative ones.
    meta('property', 'og:type', 'website'),
    meta('property', 'og:site_name', site.name),
    meta('property', 'og:locale', 'en_IN'),
    meta('property', 'og:url', canonical),
    meta('property', 'og:title', page.title),
    meta('property', 'og:description', share),
    meta('property', 'og:image', SHARE_IMAGE.url),
    meta('property', 'og:image:width', SHARE_IMAGE.width),
    meta('property', 'og:image:height', SHARE_IMAGE.height),
    meta('property', 'og:image:alt', SHARE_IMAGE.alt),
    meta('name', 'twitter:card', 'summary_large_image'),
    meta('name', 'twitter:title', page.title),
    meta('name', 'twitter:description', share),
    meta('name', 'twitter:image', SHARE_IMAGE.url),
    android.live && android.id && meta('name', 'twitter:app:id:googleplay', android.id),
    ios.live && ios.id && meta('name', 'twitter:app:id:iphone', ios.id),
    `<script type="application/ld+json">${json(page.structuredData(stores))}</script>`,
  ]
    .filter(Boolean)
    .map((line) => `    ${line}`)
    .join('\n')
}

export function renderSitemap(pages: Page[] = PAGES): string {
  const entries = pages
    .map((p) => `  <url>\n    <loc>${url(p.path)}</loc>\n    <lastmod>${p.updated}</lastmod>\n  </url>`)
    .join('\n')
  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${entries}\n</urlset>\n`
}

export function renderRobots(): string {
  return `User-agent: *\nAllow: /\n\nSitemap: ${url('/sitemap.xml')}\n`
}

/**
 * The web manifest. Once the app is live, related_applications tells Chrome on
 * Android about it: Chrome can then offer Google Play's install sheet on the
 * site, and prefers the store app to installing the website.
 */
export function renderManifest(stores: Stores): string {
  const related = [
    stores.android.live && { platform: 'play', url: stores.android.url, id: stores.android.id },
    stores.ios.live && { platform: 'itunes', url: stores.ios.url },
  ].filter(Boolean)
  const manifest = {
    name: `${site.name} — ${site.tagline}`,
    short_name: site.name,
    description: PAGES[0].description,
    start_url: '/',
    display: 'browser',
    background_color: '#040816',
    theme_color: '#040816',
    icons: [
      { src: '/icon-192.png', sizes: '192x192', type: 'image/png', purpose: 'any maskable' },
      { src: '/icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any maskable' },
    ],
    ...(related.length ? { related_applications: related, prefer_related_applications: true } : {}),
  }
  return `${JSON.stringify(manifest, null, 2)}\n`
}
