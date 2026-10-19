import { useSyncExternalStore } from 'react'

/*
 * The visitor's analytics choice, remembered in this browser. null means they
 * have not chosen yet (or reopened Cookie settings), which shows the banner.
 */
export type Consent = 'granted' | 'denied' | null

const KEY = 'hawk.analytics-consent'
const listeners = new Set<() => void>()
let current: Consent | undefined

function read(): Consent {
  try {
    const value = localStorage.getItem(KEY)
    return value === 'granted' || value === 'denied' ? value : null
  } catch {
    // Storage blocked (private mode, strict settings): ask again next visit.
    return null
  }
}

export function getConsent(): Consent {
  if (current === undefined) current = read()
  return current
}

export function setConsent(value: Consent) {
  current = value
  try {
    if (value) localStorage.setItem(KEY, value)
    else localStorage.removeItem(KEY)
  } catch {
    // Still honoured for this page view.
  }
  listeners.forEach((listener) => listener())
}

export function subscribeConsent(listener: () => void) {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

/** 'unknown' while prerendering and hydrating, so the HTML never shows a banner. */
export function useConsent(): Consent | 'unknown' {
  return useSyncExternalStore(subscribeConsent, getConsent, () => 'unknown' as const)
}
