# Pricing — the model, and what it costs to serve

## The model

| | Free | Standard | Premium |
| --- | --- | --- | --- |
| **Memory window** | 30 days | 1 year | Unlimited |
| **Restore history** | last snapshot | 3 months | Unlimited* |
| **Connected accounts** | 1 | 3 † | All |
| **Questions / day** | 4 | Unlimited | Unlimited |
| **Monthly** | — | $9 | $19 |
| **Annual** | — | $90 | $190 |

Annual is ten months — two free. Launch pricing runs below list
(`LAUNCH_PRICING=true`).

\* Restore history, kept in the user's **own** connected storage — see below.
† Not specified in the stated model; a placeholder. `app/services/billing/plans.py`.

## What each axis actually costs

Net of a 15% store commission (Apple/Google Small Business Program, under
$1M/yr): **$9 → $7.65** and **$19 → $16.15**.

**Backup costs us nothing.** Snapshots are written to the user's own connected
storage — WhatsApp's model — so "unlimited backup" is unlimited at zero
marginal cost. We hold the *record* of a snapshot; their Drive holds the bytes.
This is what keeps §43's BYOS argument intact end to end.

**Memory — the only axis we pay for, and it is cheap.**

```
     10,000 memories ≈    80,000 chunks =   1.1 GB   $0.29/mo
    100,000 memories ≈   800,000 chunks =  11.4 GB   $2.86/mo
  1,000,000 memories ≈ 8,000,000 chunks = 114.4 GB  $28.61/mo
```

Embeddings are one-time and trivial: 100K memories ≈ $6.40, once.

**"Unlimited memory" at $19 is comfortably profitable.** A user would need
roughly half a million memories — about 1,300 captures a day for a year —
before storage alone reached half the net revenue. The `index_bytes` ceilings
in `plans.py` are a runaway backstop, not a commercial limit.

> **Correction.** An earlier version of this document treated "backup" as us
> hosting the user's original files, and concluded that unlimited backup was
> loss-making above ~1 TB. That was the wrong premise: we never hold the
> originals, and the backup archive contains only the derived layer. The
> concern does not apply.

## The backup archive

```
knowra-<timestamp>.kvault          → the user's provider app folder
├── manifest.json                    format version, counts, embedding model
├── memories.jsonl                   one memory per line
├── chunks.jsonl                     text and citation anchors
├── vectors.bin                      int8 matrix, row-aligned with chunks
└── taxonomy.jsonl                   topics, entities, relations
```

Sizes, for 100,000 memories:

| Contents | Size |
| --- | ---: |
| Text + metadata only | 2.5 GB |
| \+ float32 vectors | 7.2 GB |
| \+ **int8 vectors** | **3.7 GB** |

Vectors are quantized to int8 with a per-row scale. Measured cosine similarity
after a round trip is **0.99997**, and ranking order is unchanged — so it costs
effectively nothing in retrieval quality and divides the largest part of the
archive by four. Seven gigabytes onto a new phone is not a restore anyone
completes.

**The trap worth knowing about:** embeddings from two different models are not
comparable, and mixing them does not raise an error — it returns confident
nonsense. The manifest records `embedding_model` and `embedding_dimensions`,
and restore compares them against the live model. Matching, the vectors load
straight in. Differing, they are dropped and rebuilt from the archived text —
slower, and it costs us a re-embed pass (~$6.40 per 100K memories), but
correct. `POST /v1/backup/restore/plan` surfaces which of the two will happen
*before* the user commits to it.

**One honest limitation:** a snapshot is only as reachable as the account
holding it. Sign in to a new phone with a different Google account and the
backup is invisible to us, even though the file still exists. WhatsApp has
exactly the same constraint. The `UNREACHABLE` state exists to say so plainly
rather than to show an empty restore screen.

## Two things worth deciding early

**1. The store tax is not optional.** Digital subscriptions on iOS and Android
must go through IAP. A $9 subscription nets $6.30 at the standard 30%, or
$7.65 at 15%.

> **Enroll in the Apple Small Business Program and the Google equivalent
> before launch.** Both are 15% under $1M/yr, both are opt-in, and neither is
> retroactive. This is the single highest-return hour of admin available.

Web checkout via Stripe nets $8.71 — worth offering, but it cannot be the only
path, and in-app steering toward it is restricted.

**2. Launch pricing should be an offer, not a lower list price.** A launch
price you later raise anchors everyone to the cheap number and reads as a price
rise. A *founding-member offer against the list price*, visibly time-boxed and
locked for 12 months, reads as a reward and leaves the list price intact.
Same revenue, opposite psychology. `LAUNCH_PRICES` is structured for this.

## Free tier: four questions a day

The limit is on **queries, not storage** — deliberately. Every question is a
vector search plus a rerank plus an LLM call, so it is the one axis that costs
per use rather than per month.

Search, chat and voice draw on **one shared allowance**. Metering them
separately would give a free user twelve a day and leave `/chat` — the most
expensive path — the easiest to abuse.

Enforced as a FastAPI dependency (`spend_query`) rather than inside each
handler, so a new retrieval endpoint cannot ship un-metered by omission.

## Retention: demote, never delete

A memory outside its plan's window is **demoted, not deleted**.

```
 within window          outside window            after upgrade
 ┌─────────────┐        ┌─────────────┐           ┌─────────────┐
 │ row         │        │ row         │  demote   │ row         │
 │ text        │  ────► │ text        │  ──────►  │ text        │
 │ chunks      │        │ (dropped)   │  re-embed │ chunks      │
 │ embeddings  │        │ (dropped)   │           │ embeddings  │
 └─────────────┘        └─────────────┘           └─────────────┘
   searchable             listed only               searchable
```

Three reasons, in order of importance:

1. **§36 forbids silent deletion.** A memory vault that quietly loses things on
   day 31 breaks its own promise, and free users are precisely the audience
   deciding whether to trust it.
2. **It is the cheaper design.** The expensive part is the derived layer;
   dropping it reclaims essentially the whole cost. The row and the pointer to
   the original are nearly free to keep.
3. **It is what makes upgrading work.** Expiry is measured from *capture*, not
   from the subscription — so paying restores what you already have, rather
   than only helping from that moment on. That is the difference between a
   paywall and a ransom.

The dormant count is surfaced on `GET /v1/billing/subscription`, so the app can
say *"1,204 memories are waiting"* instead of a generic upgrade prompt.
