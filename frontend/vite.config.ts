import react from '@vitejs/plugin-react'
import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vite'
import { seo } from './seo.plugin.ts'

const page = (path: string) => fileURLToPath(new URL(path, import.meta.url))

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), seo()],
  build: {
    rolldownOptions: {
      // The landing page, plus the two legal pages as pages of their own:
      // plain URLs (/privacy, /terms) that open without loading the film.
      input: {
        main: page('./index.html'),
        install: page('./install.html'),
        privacy: page('./privacy.html'),
        terms: page('./terms.html'),
        deleteAccount: page('./delete-account.html'),
      },
    },
  },
})
