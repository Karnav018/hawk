# Hawk landing page

Vite + React + TypeScript. Built from the Claude Design wireframe
`Knowra Landing Wireframes.dc.html`, option **1b, video-first**:

```
hero (film) → pain scene → hawk story → core features → footer
```

Built so far:
- **The film:** on its own for now, with no text over it; pause/sound sit bottom-left.
- **The pain scene:** a paper collage built to the user's reference image:
  - Cream paper blobs, a huge extruded condensed headline (Anton), and a serif
    subline over spaced mono body text.
  - Lost things on one side: a stressed doodle, a speech bubble, a polaroid, a
    voice note, file tags.
  - Hawk's eye in a dashed orbit on the other side. It is the app's and the
    film's eye (`components/HawkEye.tsx`), drawn from the film's paper
    shapes: cream outline ring, dark gap, cream eye, blue disc, pupil,
    highlight.
- **The story ("Why a hawk"):** one centred paragraph, the film's words ("A
  hawk sees what is almost invisible, from far away"), in white Archivo on a
  near-black navy page (#040816). Key phrases are semibold (the app has no
  Archivo italic), and an Instrument Serif italic sign-off follows. There is no
  visible title; a hidden heading labels it for screen readers.
  - **Arrival:** the words rise in one after another; the sign-off appears as
    you reach the end.
  - **With a mouse:** Hawk's eye, 44px wide, leaves the navbar's logo button,
    which stands empty meanwhile, and becomes the cursor. It looks the way it
    travels. Moving up onto the navbar, or scrolling away, sends it home. See
    `useHawkCursor.ts`.
  - A hover-recolour effect and a water-bubble lens were tried and removed at
    the user's request.
- **The footer:** the wireframe's slim closing bar on the story's navy. The
  logo and the film's last line ("Your second memory.") sit on the left;
  Privacy, Terms, the contact email (`site.email`) and the year sit on the
  right. Below 820px it becomes three rows.
- **Privacy and Terms:** `/privacy` and `/terms`, pages of their own
  (`privacy.html`, `terms.html` → `src/legal/`) on the same night page and
  footer, without the film. The privacy policy is written from what the app
  and its Firebase backend actually do. Change it whenever the data handling
  changes, especially the Gemini free-tier paragraph.
- **The navbar:** a floating pill (round logo button, section links, Install
  app) that drops in once you scroll. The floating **Install app** button shows
  only before that, so there is one install button on screen at a time.

```bash
npm install
npm run dev       # http://localhost:5173
npm run build     # type-check + production build into dist/
npm run lint
```

## SEO, prerendering and analytics

```
src/seo/pages.ts ──► seo.plugin.ts ──► every page's <head>, sitemap.xml, robots.txt
   (one entry per page)   (also fails the build on SEO mistakes)

vite build ──► vite build --ssr src/entry-server.tsx ──► scripts/prerender.mjs
 (browser)        (render() per page)                  (writes HTML into #root)
```

- **SEO registry** (`src/seo/pages.ts`): title, description, share text,
  theme colour, last-updated date and structured data (JSON-LD: Organization,
  WebSite, MobileApplication; WebPage for the legal pages) for each page.
  `seo.plugin.ts` turns it into head tags (canonical, robots, Open Graph,
  Twitter, icons, manifest), `sitemap.xml` and `robots.txt`, and stops the
  build if a title is not 10–60 characters, a description is not 70–160, or
  anything is duplicated. HTML files only carry a `<!-- seo -->` marker.
- **Prerendering**: `npm run build` renders every page to HTML at build time,
  so search engines and link previews (WhatsApp, X, LinkedIn, Slack...) see
  the full page without running JavaScript. The browser then hydrates it
  (`hydrateRoot` in `main.tsx` and `legal/mount.tsx`). This is static
  generation, not a server: pages stay on Vercel's CDN. Anything that reads
  the browser during render needs a server fallback (see `useFilmPlayer`).
- **Google Analytics 4** (`src/analytics/`): off unless the
  `VITE_GA_MEASUREMENT_ID` environment variable is set at build time. Then a
  consent banner asks first ("basic" consent mode: nothing loads from Google
  and no cookie is set before Allow); on the landing page it appears only
  after the film is scrolled past. Returning visitors who allowed it get GA
  when the page is idle. The footer's Cookie settings reopens the choice, and
  No thanks deletes the `_ga` cookies. Events: `install_click` (nav/fab),
  `film_sound`, `section_view` (pain/story), `contact_click`.
- **App stores, found at build time** (`src/seo/stores.ts`): every build asks
  Google Play (by package name) and Apple (by bundle ID, via the iTunes
  lookup API) whether Hawk is published, and passes the answer to the app as
  `__HAWK_STORES__`. Nothing to edit on launch day; the first deploy after a
  store goes live switches on:
  - the store button on `/install` (a "Coming soon" outline until then);
  - the Install buttons going straight to the phone's own store;
  - Chrome's in-page Google Play sheet (`related_applications` in the
    generated `site.webmanifest`);
  - Safari's app banner (`apple-itunes-app`), X app cards, and `downloadUrl`
    and `sameAs` in the structured data.
  A store that can't be reached counts as not live; `HAWK_SKIP_STORE_CHECK=1`
  builds offline.
- **Search console tags**: set `GOOGLE_SITE_VERIFICATION` or
  `BING_SITE_VERIFICATION` on Vercel to add their HTML verification tags.
- **Security headers** (`vercel.json`): nosniff, Referrer-Policy,
  X-Frame-Options, Permissions-Policy. HSTS is Vercel's own.

## Deploy (Vercel)

Live at **https://hawk-tan.vercel.app** (Vercel account `karnav018`, project
`hawk`), and at **https://hawkapp.in** once its DNS points at Vercel.
`hawkapp.in` and `www.hawkapp.in` are attached to the project; GoDaddy's DNS
needs the apex `A @ → 76.76.21.21`, with `www` left as GoDaddy's default
`CNAME www → @`. `vercel.json` redirects `www` to the bare domain, and HTTPS
certificates are issued by Vercel automatically.

Link previews use absolute URLs on `hawkapp.in` (`og:image` is `public/og.jpg`,
the film's end card at 1200×630). `public/robots.txt` and `public/sitemap.xml`
list the three pages.

This folder is linked (`.vercel/`), so from here:

```bash
vercel deploy --prod
```

Vercel builds from source (`npm run build`); `.vercelignore` keeps `dist/` and
`node_modules/` from being uploaded. `vercel.json` gives the hashed files in
`/assets/` (film, fonts, scripts) a one-year immutable cache, and they are
served with byte ranges (206), so the film can seek. The page itself
revalidates on every visit, so a new deploy shows up immediately.
`cleanUrls` serves `privacy.html` at `/privacy`, which is also how Vite's own
server resolves it (a `privacy/index.html` only answers `/privacy/`).

## Layout

```
index.html                    the film itself (plain HTML) + its critical CSS
install.html                  the install page (served at /install)
privacy.html, terms.html      the legal pages (served at /privacy, /terms)
delete-account.html           Google Play's account-deletion page (/delete-account)
src/
├── main.tsx                  fonts: Archivo now, serif/mono deferred
├── fonts-later.ts            the deferred faces (own chunk)
├── index.css                 tokens (navy page, cream paper, cyan, grain) + reset
├── site.ts                   name, install URL, contact email, legal links
├── assets/film/              the film and its stills (hashed at build)
├── components/               Logo, HawkEye, Nav, Footer, ButtonLink, InstallFab
├── legal/                    Privacy and Terms (LegalPage frame, *Page text, entries)
├── seo/                      pages.ts (the SEO registry), head.ts (tags, sitemap, robots)
├── analytics/                consent store, GA loader + track(), ConsentBanner
├── install/                  /install page, store routing for Install buttons
├── entry-server.tsx          render() for prerendering
├── hooks/                    useMediaQuery, useScroll (scrolled / active section / in view)
└── sections/
    ├── hero/                 transparent frame over the film; useFilmPlayer adopts it
    ├── pain/                 the pain collage: Pain.tsx (canvas + motion), doodles.tsx
    │                         (figure, bubble, orbit, polaroid, voice note)
    └── story/                why a hawk: Story.tsx (words), useHawkCursor.ts (the navbar cursor)
```

## The film

- It autoplays muted and on loop while on screen. Under
  `prefers-reduced-motion` it never starts by itself, and the poster shows instead.
- The sound button, or a click on the film, turns sound on (browsers only
  autoplay muted video). Turning sound on also resumes a paused film.
- When the visitor pauses, the film stays paused. It does not restart when the
  tab regains focus or scrolls back into view.
- It fills the screen only when the screen's shape is close to the film's.
  Otherwise it letterboxes against the film's own edge colour, so the captions
  are never cropped.

### Quality rule: the film is never re-encoded

The files in `src/assets/film/` carry the **Blender renders' own video streams,
copied bit for bit**. Only the music track is muxed in. Re-encoding for the web
visibly softened the paper texture, even at "high quality" settings. It also
bought nothing here: the 4K editor export (`hawk_video.mp4`) is an upscale of
the 1080p render with no extra detail. SSIM 0.999 after a round trip through
1080p, and the same even when the browser does the enlarging.

| File | Used when | Picture (copied) | Sound |
| --- | --- | --- | --- |
| `hawk-film-1080.mp4` | landscape | `design/blender/film/hawk_launch_film_painted.mp4` (1920×1080) | `hawk_video.mp4` |
| `hawk-film-portrait-1920.mp4` | aspect ≤ 1:1 | `design/blender/film/hawk_launch_film_portrait.mp4` (1080×1920) | same track |

The `<source>` list in `index.html` picks the file by orientation. When the
window changes shape, `useFilmPlayer` switches files without losing the
playhead.

To rebuild after the film or the music changes (run from the repo root):

```bash
M=frontend/src/assets/film
ffmpeg -i design/blender/film/hawk_launch_film_painted.mp4 -i hawk_video.mp4 -map 0:v:0 -map 1:a:0 -c copy -movflags +faststart $M/hawk-film-1080.mp4
ffmpeg -i design/blender/film/hawk_launch_film_portrait.mp4 -i hawk_video.mp4 -map 0:v:0 -map 1:a:0 -c copy -movflags +faststart $M/hawk-film-portrait-1920.mp4
ffmpeg -ss 0.2 -i design/blender/film/hawk_launch_film_painted.mp4 -frames:v 1 -q:v 2 $M/hawk-film-poster.jpg
ffmpeg -ss 0.2 -i design/blender/film/hawk_launch_film_portrait.mp4 -frames:v 1 -q:v 2 $M/hawk-film-portrait-poster.jpg
```

`-c copy` keeps the picture untouched. `-movflags +faststart` moves the index
to the front of the file, so playback can begin before the whole file has
downloaded. To check a rebuild, both lines should print the same hash:

```bash
ffmpeg -v error -i frontend/src/assets/film/hawk-film-1080.mp4 -map 0:v -c copy -f md5 -
ffmpeg -v error -i design/blender/film/hawk_launch_film_painted.mp4 -map 0:v -c copy -f md5 -
```

If a sharper film is wanted, render it at a higher resolution in Blender and
add it as the first `<source>` in `index.html`, with a media query such as
`(min-width: 1400px) and (min-resolution: 2dppx)`. Don't upscale an export.

## The pain scene: how it moves

Every element is two boxes (`Layer` in `Pain.tsx`):
- **`.layer`:** places it on the canvas, in % of the section, with a separate
  phone layout. It drifts with the mouse by its depth (`--d`).
- **`.piece`:** plays the entrance the first time the section is 30% in view,
  then idles:
  - **Arrival:** blobs pop, paper is tossed down and settles, and the lines
    draw themselves in via `pathLength="1"` + `stroke-dashoffset`.
  - **Idle:** blobs wobble, props bob, the figure shudders, the voice note's
    waveform plays, and sparkles twinkle.
- **Hawk's eye:** opens after it lands, double-blinks every six seconds like
  the app's READY state, and its disc follows the pointer (0.38 across and
  0.22 up or down, the app's gaze range). A paper card
  travels the dashed orbit (SVG `animateMotion`).

**Phones and portrait tablets** use a separate composition: design 02m,
"Pain — mobile, 390×844", in the Claude Design file `Canvas-3.dc.html`. It is a
canvas measured in `--u`, a hundredth of its width, and exactly one screen
tall (`100lvh`, so the film never peeks in above it). Vertical positions are
percentages of the section. `u` is `1vw` unless the screen is too short to hold
the collage (200u), in which case it shrinks to fit and the canvas is centred.

Everything animates `transform`, `translate`, `rotate`, `scale` or `opacity`,
so the compositor handles it. The mouse position is written straight to CSS
variables once per frame; React never re-renders for motion. Reduced motion
shows the finished collage, still.

## Speed

The film is fast to start without touching its quality:

- **It is plain HTML.** The `<video>` and its still are in `index.html`, so the
  browser requests them while it parses the page. When React created them, the
  video was only requested after the app's JavaScript had loaded.
- **Something is on screen at once.** The first paint shows a 0.4 KB blurred copy
  of the opening frame (inline CSS). Then the full still loads, at high
  priority, then the film.
- **No third-party requests.** Fonts are self-hosted. Only Archivo loads with
  the page; the serif and mono faces used further down load once the film is
  playing or the visitor scrolls.
- **The files start fast.** Each has its index (`moov`) at the front and a
  keyframe at 0:00. The first frame needs about 130 KB (landscape) or 210 KB
  (portrait).

Measured with Chrome on a throttled connection (production build, median of 3
runs, ms from navigation):

| | video requested | still shown | first frame |
| --- | --- | --- | --- |
| 4G (10 Mbps, 60 ms), before | 212 | 423 | 573 |
| 4G, after | 69 | 338 | 510 |
| slow 4G (4 Mbps, 150 ms), before | 493 | 1039 | 1409 |
| slow 4G, after | 164 | 844 | 1266 |

What's left is bandwidth: shrinking the frames would cut it further, but only
by lowering quality.

**When deploying**, serve `/assets/*` with
`Cache-Control: public, max-age=31536000, immutable`. The filenames are content
hashes, so a changed file gets a new name, and repeat visits play straight from
the disk cache. Serve `index.html` with `Cache-Control: no-cache`. Put it behind
a CDN that supports HTTP range requests (all the major ones do), so the film
streams from an edge close to the visitor.

## Still to do

- `site.installUrl` is a placeholder (`#install`) until the store listings exist.
- The remaining sections of the wireframe.
