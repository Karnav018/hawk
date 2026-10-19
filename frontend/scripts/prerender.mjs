// After both builds: writes each page's rendered HTML into its built file.
//
//   vite build              → dist/           (the browser pages, empty #root)
//   vite build --ssr ...    → dist-ssr/       (render() for each page)
//   node scripts/prerender  → dist/*.html     (#root filled), dist-ssr removed
import { readFile, rm, writeFile } from 'node:fs/promises'

const root = new URL('../', import.meta.url)
const { render, PAGES } = await import(new URL('dist-ssr/entry-server.js', root).href)
const EMPTY_ROOT = '<div id="root"></div>'

for (const page of PAGES) {
  const file = new URL(`dist/${page.file}`, root)
  const html = await readFile(file, 'utf8')
  if (!html.includes(EMPTY_ROOT)) throw new Error(`prerender: ${page.file} has no ${EMPTY_ROOT}`)
  const body = render(page.id)
  await writeFile(file, html.replace(EMPTY_ROOT, `<div id="root">${body}</div>`))
  console.log(`prerendered ${page.path.padEnd(9)} → dist/${page.file} (${(body.length / 1024).toFixed(1)} kB)`)
}

await rm(new URL('dist-ssr/', root), { recursive: true, force: true })
