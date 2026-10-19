# Remaining screens — Hawk v3

Source: `design/mobile-application-design-planning/project/Hawk App v3.dc.html`
(38 screens, export of 22 Sep 16:20). **IDs shifted in this export**: `1y HOME —
VOICE DEFAULT` was inserted, so everything from the old `1y` moved down one
letter. These are the *new* IDs.

Audited by copy, not by file name: each screen's visible strings were grepped
against `app/lib`. A route that exists but whose copy is the old design counts
as partial, not built.

**Now: 37 of 37 ours built (1c is Google's own picker).** Original audit: 21 built · 8 partial · 8 missing.

---

## Batch 1 — states on screens that already exist

No new routes. Cheapest, and 2a is a live hole: a search with no matches
currently shows an empty result stack with no explanation at all.

- [x] **2a · NOTHING FOUND** — done 22 Sep
  `No match` / `YOU ASKED` + the question / "Nothing in your library matches.
  It may not be indexed yet." / `TRY THIS` list: *Index 9,570 more Drive files*
  (`Not searched yet`), *Add it now* (`Scan, upload or paste a link`),
  *Search filenames instead* (`Exact text match`) / `Ask again`
  → empty state in `result_stack_page` + `chat_thread`

- [x] **1v · LIBRARY — QUOTA REACHED** — done 22 Sep (DORMANT wording, Keep -> upgrade)
  `Storage full` / `15 / 15 GB` / "New uploads are paused. Free up space or
  move to Pro for 1 TB." / `Free up` + `Go Pro` / `Expiring soon` `3 ITEMS`
  with `DELETED IN 2 DAYS` + `Keep`
  → banner + expiring section in `library_page`

- [x] **1w · ASK LIMIT — BLOCKING SHEET** — done 22 Sep
  `You've used all 100` `asks this month` / "Your library stays indexed and
  searchable. Asking resumes on 1 Oct, or right now on Pro." / `Asks used`
  `100 / 100` `RESETS IN 9 DAYS` / `Unlock unlimited asks` + `Wait until 1 Oct`
  → `PlanGate` exists; copy and the sheet do not

## Batch 2 — account

- [x] **2l · DELETE ACCOUNT** — done 22 Sep — `Delete your account?` / what goes
  (`1,516 indexed memories`, `Pro subscription, effective now`).
  Confirm dialog exists; the screen does not.
- [x] **2k · PRIVACY AND DATA** — done 22 Sep (1 of 6 rows live) — `Everything is indexed on this device` /
  `Crash reports` (`Anonymous, no file names`) / `Lock with Face ID`.
  `_PrivacySheet` exists but predates this design.
- [x] **1u · PRO ACTIVE** — done 22 Sep (card/receipts not exposed by the stores) — `YOUR PLAN` `Pro` `TRIAL · 6 DAYS` /
  `Asks this month` `42 · unlimited` / `Billing and receipts` /
  `Payment method` / `Cancel subscription`
- [x] **2j · BILLING AND RECEIPTS** — ~~BLOCKED~~ built in Phase 2 below — `NEXT CHARGE` `$96.00` / `Visa ···· 4218`
  `Change` / `RECEIPTS` rows / `Export all receipts`

## Batch 3 — capture

- [x] **2c · IMAGES — PICK OR CAPTURE** — ~~BLOCKED~~ built in Phase 2 below — "Text inside images is read and
  indexed too." / `Index 3 images`
- [x] **2d · LINK** — done 22 Sep — `Paste a public URL` / "The page is read once and
  indexed. Pages behind a login won't work." (`AddLinkSheet` exists, copy differs)
- [x] **2b · FILES — MULTI-SELECT** — multi-pick done 22 Sep; in-app browser impossible on iOS — `4 SELECTED` / `Search this device` /
  filter chips `Recent PDF Docs Folders` / `TO INDEX` `4 FILES · 7.4 MB` /
  `Index 4 files`
- [x] **2g · INDEXING QUEUE** — ~~BLOCKED~~ built in Phase 2 below — `00:22 LEFT` `3 / 4` `7.4 MB` / per-row states
  `DONE` `READING TEXT` `QUEUED` / `Password protected` + `Retry` /
  `Keep going in the background`

## Batch 4 — viewers

- [x] **2i · IMAGE VIEWER** — done 22 Sep — inline rendering landed 22 Sep; the zoom/pan
  screen with `solo` / `team` / `$29/seat` overlay has not
- [x] **2h · AUDIO PLAYER** — ~~BLOCKED~~ built in Phase 2 below — `18:20 / 41:07` scrubber / `TRANSCRIPT` with
  timestamped lines

## Batch 5 — blocked or deliberately deferred

- [x] **1t · PAYMENT SHEET** — ~~BLOCKED~~ built in Phase 2 below — `7 DAYS FREE, THEN $96/YR` / `Add a card` /
  `Confirm with Face ID`. UI only; real charging is the store's.
- [x] **2e · SCAN** — ~~BLOCKED~~ built in Phase 2 below — `CaptureKind.isAvailable => this != scan` is a deliberate
  decision: a tile that opened the camera and produced a crooked photograph is
  worse than one that says it is not ready. Needs edge detect + de-skew.
- [x] **2f · SPEAK — RECORDING** — ~~BLOCKED~~ built in Phase 2 below — hands off to the orb today; confirm that is
  the intent rather than a gap.

---

## Notes

- `1t` and `2j` need the Cloud Functions deployed to show anything real
  (blocked on Blaze). Build the UI against the shape they will return.
- Every screen must be reachable: a built screen with no route in
  `app_router.dart` is not done.
- `flutter analyze` clean + full suite green after each screen.

---

## Phase 2 — the seven, built anyway (23 Sep)

The user reaffirmed after the blockers were flagged. Each is built around the
part the platform owns, never faking that part.

- [x] **2g · INDEXING QUEUE** — done 23 Sep. The batch from 2b is client-side, so its
  per-file state is ours: watch each captured memory's `ProcessingStatus`.
  Needs `MemoryRepository.watchMemories(ids)`. No new package.
- [x] **2f · SPEAK — RECORDING** — done 23 Sep. `SpeechRecogniser` already transcribes on
  device. Dictate, then save the transcript as a `voiceNote` memory. The Speak
  tile opens this instead of the orb. No new package.
- [x] **1t · PAYMENT SHEET** — done 23 Sep. A pre-confirmation between choosing a plan and
  the store's own sheet: plan, trial terms, what is charged when. The card and
  Face ID stay the store's. No new package.
- [x] **2j · BILLING AND RECEIPTS** — done 23 Sep. The backend already verifies every
  purchase; make it *keep* a receipt per period (price captured at purchase,
  since the catalogue deliberately holds none). "Payment method" deep-links to
  the store's own management page instead of printing a card we never see.
- [x] **2c · IMAGES — PICK OR CAPTURE** — done 23 Sep. Review grid for multi-picked images,
  plus a Camera tile. Adds `image_picker`.
- [x] **2h · AUDIO PLAYER** — done 23 Sep. Playback + transcript. Adds `just_audio`.
  Timestamps only if the index holds them; otherwise the transcript is shown
  untimed rather than with invented times.
- [x] **2e · SCAN** — done 23 Sep. Native document scanners (VisionKit on iOS, ML Kit on
  Android) do edge detection and de-skew themselves. Adds
  `cunning_document_scanner`.


---

## Phase 3 — design parity (23 Sep)

A re-audit after phase 2 found the screens *exist* but these still differ from
the design. Tasks 16–21 in `tasks/`.

- [x] **16 · ALL SCREENS** — flat v3 ground; the v2 wash paints regardless of `ambientOpacity`
- [x] **17 · 1y HOME — VOICE** — subtitle + suggestion chips from real memories; "1 MEMORY READY"
- [x] **18 · 1z HOME — CHAT** — new copy, START WITH prompts, "Ask anything…"
- [x] **19 · 1x ALERT PATTERNS** — five of six components missing
- [x] **20 · 1s PRICING** — design layout on the real Standard + Premium; plan lines from the backend table (`list_products` → `plans`)
- [x] **21 · SMALL GAPS** — 1i 1j 1u 1w 2i
