/*
 * Is Hawk on Google Play and the App Store yet? Asked once per build (by
 * seo.plugin.ts), so the install buttons, Chrome's install prompt, Safari's
 * app banner and the structured data switch themselves on with the first
 * deploy after each store goes live. Nothing to edit on launch day: the Play
 * URL follows from the package name, and the App Store ID is looked up from
 * the bundle ID.
 */
export type Store = { live: boolean; url: string | null; id: string | null }
export type Stores = { android: Store; ios: Store }

export const NOT_LIVE: Store = { live: false, url: null, id: null }

const TIMEOUT_MS = 6000

async function googlePlay(packageName: string): Promise<Store> {
  const url = `https://play.google.com/store/apps/details?id=${packageName}`
  // An unpublished package is a 404; a live one is a 200.
  const res = await fetch(`${url}&hl=en`, { signal: AbortSignal.timeout(TIMEOUT_MS) })
  return res.ok ? { live: true, url, id: packageName } : NOT_LIVE
}

type Lookup = { results?: { trackId: number; trackViewUrl: string }[] }

async function appStore(bundleId: string): Promise<Store> {
  // India first (the .in audience), then the US storefront.
  for (const country of ['in', 'us']) {
    const res = await fetch(`https://itunes.apple.com/lookup?bundleId=${bundleId}&country=${country}`, {
      signal: AbortSignal.timeout(TIMEOUT_MS),
    })
    const app = ((await res.json()) as Lookup).results?.[0]
    if (app) return { live: true, id: String(app.trackId), url: app.trackViewUrl.split('?')[0] }
  }
  return NOT_LIVE
}

/** Never fails the build: a store that can't be reached counts as not live. */
export async function discoverStores(app: { androidPackage: string; iosBundleId: string }, { skip = false } = {}) {
  const notes: string[] = []
  const check = async (name: string, job: () => Promise<Store>) => {
    if (skip) return NOT_LIVE
    try {
      const store = await job()
      notes.push(`${name}: ${store.live ? `live (${store.url})` : 'not published yet'}`)
      return store
    } catch (error) {
      notes.push(`${name}: could not check (${(error as Error).message}), treated as not published`)
      return NOT_LIVE
    }
  }
  const [android, ios] = await Promise.all([
    check('Google Play', () => googlePlay(app.androidPackage)),
    check('App Store', () => appStore(app.iosBundleId)),
  ])
  return { stores: { android, ios } satisfies Stores, notes }
}
