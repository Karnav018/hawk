import { site } from '../site.ts'
import type { Stores } from './stores.ts'

/*
 * Every page's search and link-share metadata, in one place. The build reads
 * this (seo.plugin.ts) to write each page's <head>, sitemap.xml, robots.txt
 * and the web manifest, and refuses to build if a page breaks the rules in
 * validatePages(). To add a page: add it here, add its HTML entry to
 * vite.config.ts, and its view to src/entry-server.tsx.
 */

export const SITE_URL = 'https://hawkapp.in'

export type PageId = 'home' | 'install' | 'privacy' | 'terms' | 'delete-account'

export type Page = {
  id: PageId
  /** The HTML entry, relative to the project root. */
  file: string
  /** The public URL path (Vercel serves privacy.html at /privacy). */
  path: string
  title: string
  /** What search results show under the title. */
  description: string
  /** What link previews show; defaults to the description. */
  shareDescription?: string
  themeColor: string
  /** The day the page's content last changed (sitemap lastmod). */
  updated: string
  /** JSON-LD. Store links appear once the build finds the app live. */
  structuredData: (stores: Stores) => object[]
}

export const SHARE_IMAGE = {
  url: `${SITE_URL}/og.jpg`,
  width: 1200,
  height: 630,
  alt: 'Hawk’s eye above the words: Hawk, your second memory.',
}

/** Names people search for. Google uses these to recognise the site's name. */
const ALTERNATE_NAMES = ['Hawk app', 'HawkApp', 'Hawk memory app']

export const url = (path: string) => `${SITE_URL}${path}`

const ORGANIZATION_ID = url('/#organization')
const WEBSITE_ID = url('/#website')
const APP_ID = url('/#app')

const SCHEMA = { '@context': 'https://schema.org' }

export const liveStoreUrls = (stores: Stores) =>
  [stores.android, stores.ios].flatMap((s) => (s.live && s.url ? [s.url] : []))

const operatingSystems = (stores: Stores) => {
  const live = [stores.android.live && 'Android', stores.ios.live && 'iOS'].filter(Boolean)
  return (live.length ? live : ['Android', 'iOS']).join(', ')
}

/** The app itself, as search engines should know it. */
const app = (stores: Stores) => {
  const storeUrls = liveStoreUrls(stores)
  return {
    ...SCHEMA,
    '@type': 'MobileApplication',
    '@id': APP_ID,
    name: site.name,
    alternateName: ALTERNATE_NAMES,
    description:
      'Hawk is your second memory: ask for any photo, document or voice note in your own words, and it finds the actual file, wherever it lives.',
    operatingSystem: operatingSystems(stores),
    applicationCategory: 'UtilitiesApplication',
    offers: { '@type': 'Offer', price: '0', priceCurrency: 'INR' },
    installUrl: url('/install'),
    ...(storeUrls.length ? { downloadUrl: storeUrls, sameAs: storeUrls } : {}),
    publisher: { '@id': ORGANIZATION_ID },
  }
}

const webPage = (page: Omit<Page, 'structuredData' | 'themeColor'>, extra: object = {}) => ({
  ...SCHEMA,
  '@type': 'WebPage',
  name: page.title,
  url: url(page.path),
  description: page.description,
  dateModified: page.updated,
  inLanguage: 'en',
  isPartOf: { '@id': WEBSITE_ID },
  publisher: { '@id': ORGANIZATION_ID },
  ...extra,
})

const legalPage = (page: Omit<Page, 'structuredData' | 'themeColor'>): Page => ({
  ...page,
  themeColor: '#040816',
  structuredData: () => [webPage(page)],
})

const installPage: Omit<Page, 'structuredData' | 'themeColor'> = {
  id: 'install',
  file: 'install.html',
  path: '/install',
  title: 'Download Hawk App for Android and iPhone',
  description:
    'Get Hawk, the memory app that finds any photo, document or voice note when you ask in your own words. For Android and iPhone.',
  updated: '2026-09-27',
}

export const PAGES: Page[] = [
  {
    id: 'home',
    file: 'index.html',
    path: '/',
    title: 'Hawk App — your second memory for photos, files and notes',
    description:
      'Hawk is a memory app: ask for any photo, document or voice note in your own words and it finds the file. Your memories stay where they live.',
    shareDescription: 'You remember it. Hawk helps you see it.',
    themeColor: '#0c1017',
    updated: '2026-09-27',
    structuredData: (stores) => {
      const storeUrls = liveStoreUrls(stores)
      return [
        {
          ...SCHEMA,
          '@type': 'Organization',
          '@id': ORGANIZATION_ID,
          name: site.name,
          alternateName: ALTERNATE_NAMES,
          url: url('/'),
          logo: url('/icon-512.png'),
          email: site.email,
          ...(storeUrls.length ? { sameAs: storeUrls } : {}),
        },
        {
          ...SCHEMA,
          '@type': 'WebSite',
          '@id': WEBSITE_ID,
          name: site.name,
          alternateName: ALTERNATE_NAMES,
          url: url('/'),
          inLanguage: 'en',
          publisher: { '@id': ORGANIZATION_ID },
        },
        app(stores),
      ]
    },
  },
  {
    ...installPage,
    themeColor: '#040816',
    structuredData: (stores) => [webPage(installPage, { mainEntity: { '@id': APP_ID } }), app(stores)],
  },
  legalPage({
    id: 'privacy',
    file: 'privacy.html',
    path: '/privacy',
    title: 'Privacy Policy — Hawk',
    description:
      'What Hawk collects, why, which companies process it for Hawk, and how to delete your data or your whole account.',
    updated: '2026-09-27',
  }),
  legalPage({
    id: 'terms',
    file: 'terms.html',
    path: '/terms',
    title: 'Terms of Service — Hawk',
    description:
      'The terms for using Hawk: your content, acceptable use, answers written by AI, plans and payments, and leaving.',
    updated: '2026-09-27',
  }),
  // Google Play's "Delete account URL": how to delete without the app.
  legalPage({
    id: 'delete-account',
    file: 'delete-account.html',
    path: '/delete-account',
    title: 'Delete your Hawk account',
    description:
      'How to delete your Hawk account and data, in the app or by email without it: what is deleted, what is kept, and how long it takes.',
    updated: '2026-09-27',
  }),
]

/** Rules every page must pass, or the build stops. */
export function validatePages(pages: Page[] = PAGES): string[] {
  const problems: string[] = []
  const seen = { title: new Set<string>(), description: new Set<string>(), path: new Set<string>() }
  for (const p of pages) {
    const at = `${p.id}:`
    // Google cuts titles near 60 characters and descriptions near 160.
    if (p.title.length < 10 || p.title.length > 60) problems.push(`${at} title is ${p.title.length} chars (10–60)`)
    if (p.description.length < 70 || p.description.length > 160)
      problems.push(`${at} description is ${p.description.length} chars (70–160)`)
    if (!p.path.startsWith('/')) problems.push(`${at} path must start with /`)
    if (!/^\d{4}-\d{2}-\d{2}$/.test(p.updated)) problems.push(`${at} updated must be YYYY-MM-DD`)
    for (const key of ['title', 'description', 'path'] as const) {
      if (seen[key].has(p[key])) problems.push(`${at} duplicate ${key}`)
      seen[key].add(p[key])
    }
  }
  return problems
}
