import { useSyncExternalStore, type MouseEvent } from 'react'
import { track } from '../analytics/ga'
import { site } from '../site'
import type { Store } from '../seo/stores'

/*
 * Where "Install app" goes. The prerendered HTML always points at /install
 * (both stores); in the browser, a phone goes straight to its own store once
 * Hawk is live there. Chrome on Android goes one better: with the app listed
 * in the web manifest (related_applications), it offers Google Play's install
 * sheet in place, without leaving the site.
 */
export const STORES = __HAWK_STORES__

type Platform = 'android' | 'ios' | 'other'

function platform(): Platform {
  const ua = navigator.userAgent
  if (/android/i.test(ua)) return 'android'
  // iPadOS reports itself as a Mac, but a Mac has no touch screen.
  if (/iphone|ipad|ipod/i.test(ua) || (/macintosh/i.test(ua) && navigator.maxTouchPoints > 1)) return 'ios'
  return 'other'
}

const storeFor = (p: Platform): Store | null => (p === 'other' ? null : STORES[p])

function installHref(): string {
  const store = storeFor(platform())
  return store?.live && store.url ? store.url : site.installUrl
}

const noSubscribe = () => () => {}

/** The Install link's href: /install in the HTML, the phone's store once hydrated. */
export function useInstallHref(): string {
  return useSyncExternalStore(noSubscribe, installHref, () => site.installUrl)
}

type InstallPromptEvent = Event & { prompt: () => Promise<void> }
let deferredPrompt: InstallPromptEvent | null = null

/** Call once per page, early: Chrome fires this at most once. */
export function listenForInstallPrompt() {
  window.addEventListener('beforeinstallprompt', (event) => {
    event.preventDefault()
    deferredPrompt = event as InstallPromptEvent
  })
}

export function onInstallClick(event: MouseEvent, placement: string) {
  const p = platform()
  track('install_click', { placement, platform: p })
  if (p === 'android' && deferredPrompt) {
    event.preventDefault()
    void deferredPrompt.prompt()
    deferredPrompt = null
  }
}
