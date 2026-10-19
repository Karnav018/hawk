export const site = {
  name: 'Hawk',
  tagline: 'Your second memory',
  // The install page: both stores, "coming soon" until each is live. On a
  // phone the Install buttons skip it for that phone's store (src/install).
  installUrl: '/install',
  // The same IDs as the app's build (app/android, app/ios). The build looks
  // the store listings up from these (src/seo/stores.ts).
  app: {
    androidPackage: 'in.hawkapp.app',
    iosBundleId: 'in.hawkapp.app',
  },
  email: 'karnav.p.018@gmail.com',
  // Their own pages (privacy.html, terms.html), served without the .html.
  legalLinks: [
    { label: 'Privacy', href: '/privacy' },
    { label: 'Terms', href: '/terms' },
  ],
} as const
