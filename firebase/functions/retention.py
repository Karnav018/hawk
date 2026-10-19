"""Retention — memories outside the plan's window go dormant, and come back.

§36: demoted, never deleted. A dormant memory stays in the library and its
chunks stay where they are, marked `recallState: dormant`, so no search on
the phone and no answer on the server uses it — and an upgrade flips it back
at once, with nothing to read again.

Three ways in:

* [retention_sweep], daily — the clock. Memories whose window has run out.
* [on_plan_changed], a trigger on the subscription document — purchase,
  restore, renewal, lapse — so an upgrade revives and a lapse demotes without
  waiting for the sweep. A trigger rather than a line in `verify_purchase`,
  because walking a large library can outlast a sixty-second callable.
* `api.apply_retention`, the callable.

**Until 2026-09-27 none of this ran.** `recallExpiresAt` was stamped at
capture and nothing ever read it on a schedule, so a free user's memories
never expired; and the one demotion path wrote the memory document only,
while the phone's index reads the *chunks*. Every change of state now goes
to the chunks first (`chunk_store.set_recall_state`, which bumps `updatedAt`
so delta sync sees it), and `chunkRecall` on the memory records what its
chunks were last set to, so a memory whose chunks disagree is healed.

The rule is [decide], which touches no database.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, datetime

from firebase_admin import firestore
from firebase_functions import options, scheduler_fn
from firebase_functions.firestore_fn import Event, on_document_written

import billing
import chunk_store

#: Memories read per page by the sweep, and the most it settles in one run —
#: the next day's run carries on from wherever this one stopped.
PAGE = 400
MAX_PER_RUN = 5_000


@dataclass(frozen=True, slots=True)
class Decision:
    #: "demote", "promote", "heal", "restamp" — or None for nothing to do.
    action: str | None
    #: Fields to write on the memory. Empty when [action] is None.
    update: dict = field(default_factory=dict)

    @property
    def chunks_to(self) -> str | None:
        """The state this memory's chunks must be set to first, if any."""
        return self.update.get("chunkRecall")


def decide(  # noqa: PLR0911 — one return per case reads better
    data: dict, entitlements: billing.Entitlements, now: datetime
) -> Decision:
    """What retention does to one memory under the plan in force [now]."""
    created = data.get("createdAt")
    if created is None:
        return Decision(None)
    expires = billing.recall_expiry(billing._as_datetime(created), entitlements)
    expired = expires is not None and expires <= now
    state = data.get("recallState", "active")
    # Chunks are written with the memory's state, so an unrecorded value
    # means "as written", which is active unless the memory was dormant then.
    chunks_at = data.get("chunkRecall", "active")

    # Dormant because its source was disconnected: the connector owns that
    # state, and no plan revives it — reconnecting does.
    if data.get("sourceAvailable") is False:
        if state == "dormant" and chunks_at != "dormant":
            return Decision("heal", {"chunkRecall": "dormant"})
        return Decision(None)

    if expired and state == "active":
        return Decision(
            "demote",
            {"recallState": "dormant", "recallExpiresAt": expires, "chunkRecall": "dormant"},
        )
    if not expired and state == "dormant":
        update = {"recallState": "active", "recallExpiresAt": expires, "chunkRecall": "active"}
        if not data.get("chunkCount"):
            # Nothing indexed to flip back: read it again.
            update["status"] = "extracted"
        return Decision("promote", update)
    if state != chunks_at:
        return Decision("heal", {"chunkRecall": state})
    stored = data.get("recallExpiresAt")
    stored_at = billing._as_datetime(stored) if stored is not None else None
    if stored_at != expires:
        # The window moved (a plan change the hook missed, a test account
        # stamped with Free's): keep the sweep's index honest.
        return Decision("restamp", {"recallExpiresAt": expires})
    return Decision(None)


def settle(db, docs: list, entitlements_of, now: datetime) -> dict[str, int]:
    """Apply [decide] to [docs]: chunks first, then the memories.

    Chunks first so a failure part-way leaves `chunkRecall` saying the old
    state, and the next run heals it — the other order would record a state
    the chunks never reached. [entitlements_of] maps a uid to its plan.
    """
    counts = {"demote": 0, "promote": 0, "heal": 0, "restamp": 0}
    decided = []
    flips: dict[str, list[str]] = {"active": [], "dormant": []}
    for doc in docs:
        data = doc.to_dict() or {}
        decision = decide(data, entitlements_of(data.get("userId")), now)
        if decision.action is None:
            continue
        decided.append((doc, decision))
        counts[decision.action] += 1
        if decision.chunks_to:
            flips[decision.chunks_to].append(doc.id)

    for state, ids in flips.items():
        if ids:
            chunk_store.set_recall_state(db, ids, state)

    batch = db.batch()
    pending = 0
    for doc, decision in decided:
        batch.update(doc.reference, {**decision.update, "updatedAt": now})
        pending += 1
        if pending >= PAGE:
            batch.commit()
            batch = db.batch()
            pending = 0
    if pending:
        batch.commit()
    return counts


def entitlements_for(db, uid: str) -> billing.Entitlements:
    """The plan in force for [uid], test accounts included — by email too,
    which only the profile knows here."""
    user = db.collection("users").document(uid)
    subscription = user.collection("subscription").document("current").get()
    profile = user.get()
    email = (profile.to_dict() or {}).get("email") if profile.exists else None
    return billing.resolve_for_user(
        uid, subscription.to_dict() if subscription.exists else None, email=email
    )


def apply(db, uid: str, entitlements: billing.Entitlements, now: datetime) -> dict[str, int]:
    """Every memory of one user, against [entitlements]."""
    docs = list(db.collection("memories").where("userId", "==", uid).stream())
    return settle(db, docs, lambda _: entitlements, now)


def sweep(db, now: datetime) -> dict[str, int]:
    """Memories whose stamped window has ended, each re-checked against its
    owner's plan as it is today."""
    plans: dict[str, billing.Entitlements] = {}

    def plan(uid: str | None) -> billing.Entitlements:
        if not uid:
            return billing.entitlements_for(billing.FREE)
        if uid not in plans:
            plans[uid] = entitlements_for(db, uid)
        return plans[uid]

    total = {"demote": 0, "promote": 0, "heal": 0, "restamp": 0}
    last = None
    seen = 0
    while seen < MAX_PER_RUN:
        query = (
            db.collection("memories")
            .where("recallState", "==", "active")
            .where("recallExpiresAt", "<", now)
            .order_by("recallExpiresAt")
            .limit(PAGE)
        )
        if last is not None:
            query = query.start_after(last)
        docs = list(query.stream())
        if not docs:
            break
        for key, value in settle(db, docs, plan, now).items():
            total[key] += value
        last = docs[-1]
        seen += len(docs)
        if len(docs) < PAGE:
            break
    return total


@scheduler_fn.on_schedule(
    schedule="every day 02:30",
    region="us-central1",
    memory=options.MemoryOption.MB_512,
    timeout_sec=540,
)
def retention_sweep(event: scheduler_fn.ScheduledEvent) -> None:
    """Demote what the clock has aged out."""
    counts = sweep(firestore.client(), datetime.now(UTC))
    print(f"[knowra] retention_sweep {counts}")


@on_document_written(
    document="users/{userId}/subscription/{docId}",
    region="us-central1",
    memory=options.MemoryOption.MB_512,
    timeout_sec=540,
)
def on_plan_changed(event: Event) -> None:
    """A purchase, restore, renewal or lapse: re-settle this user's library
    under the plan now in force, so an upgrade brings memories back at once."""
    uid = event.params.get("userId")
    if not uid:
        return
    db = firestore.client()
    counts = apply(db, uid, entitlements_for(db, uid), datetime.now(UTC))
    print(f"[knowra] plan_changed uid={uid} {counts}")
