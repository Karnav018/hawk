import type { Plugin } from 'vite'
import { renderHead, renderManifest, renderRobots, renderSitemap, type Verification } from './src/seo/head.ts'
import { PAGES, validatePages } from './src/seo/pages.ts'
import { discoverStores, type Stores } from './src/seo/stores.ts'
import { site } from './src/site.ts'

const MARKER = '<!-- seo -->'

/**
 * The site's SEO, from src/seo/pages.ts: each page's <head> (in dev and in
 * the build), sitemap.xml, robots.txt and site.webmanifest. Also asks the
 * app stores whether Hawk is live (src/seo/stores.ts) and hands the answer to
 * the app as __HAWK_STORES__. Stops the build on SEO mistakes.
 */
export function seo(): Plugin {
  let stores: Stores
  const verification: Verification = {
    google: process.env.GOOGLE_SITE_VERIFICATION,
    bing: process.env.BING_SITE_VERIFICATION,
  }

  return {
    name: 'hawk-seo',

    async config() {
      // HAWK_SKIP_STORE_CHECK=1 builds offline (every store counts as not live).
      const found = await discoverStores(site.app, { skip: Boolean(process.env.HAWK_SKIP_STORE_CHECK) })
      stores = found.stores
      console.log(`[hawk-seo] app stores: ${found.notes.join('; ')}`)
      return { define: { __HAWK_STORES__: JSON.stringify(stores) } }
    },

    buildStart() {
      const problems = validatePages()
      if (problems.length) this.error(`SEO check failed:\n  ${problems.join('\n  ')}`)
    },

    configureServer(server) {
      // The build emits the manifest; serve the same one in dev.
      server.middlewares.use('/site.webmanifest', (_req, res) => {
        res.setHeader('Content-Type', 'application/manifest+json')
        res.end(renderManifest(stores))
      })
    },

    transformIndexHtml(html, ctx) {
      const page = PAGES.find((p) => `/${p.file}` === ctx.path)
      if (!page) throw new Error(`hawk-seo: ${ctx.path} is not in src/seo/pages.ts`)
      if (!html.includes(MARKER)) throw new Error(`hawk-seo: ${ctx.path} has no ${MARKER} in its <head>`)
      return html.replace(MARKER, renderHead(page, stores, verification).trimStart())
    },

    generateBundle(options) {
      // Only the browser build ships these; the prerender (SSR) build does not.
      if (options.dir?.endsWith('dist-ssr')) return
      this.emitFile({ type: 'asset', fileName: 'sitemap.xml', source: renderSitemap() })
      this.emitFile({ type: 'asset', fileName: 'robots.txt', source: renderRobots() })
      this.emitFile({ type: 'asset', fileName: 'site.webmanifest', source: renderManifest(stores) })
    },
  }
}
