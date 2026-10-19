"""Plans and entitlements.

Ported from `backend/app/services/billing/` — the logic is storage-agnostic, so
the move to Firestore did not change any of it. Kept as pure functions with no
Firestore imports so it stays unit-testable without an emulator.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

import firestore_test_accounts

MIB = 1024**2
GIB = 1024**3

FREE = "free"
STANDARD = "standard"
PREMIUM = "premium"


@dataclass(frozen=True, slots=True)
class Entitlements:
    """What a tier grants, per axis.

    Deliberately not one comparable "level": the tiers do not nest cleanly, and
    collapsing them into a rank is how billing bugs start.
    """

    tier: str
    #: Days a memory stays searchable. None = forever.
    memory_window_days: int | None
    #: Days of device-restore history, kept in the user's own storage.
    backup_window_days: int | None
    #: Fair-use ceiling on the derived layer we host — never their files.
    index_bytes: int | None
    connected_accounts: int | None
    #: Answers per [ANSWER_WINDOW_HOURS], each coming back that long after it
    #: was used. None = no ceiling. See `usage`.
    window_queries: int | None
    #: Answers per week — the cost cap, reset Monday 00:00 in the user's zone.
    weekly_queries: int | None
    #: Bytes of the user's own files kept in Firebase Storage, so a capture
    #: can be reopened from any device. Separate from [index_bytes] because
    #: they are different costs bought for different reasons: the index is
    #: what makes a memory *findable*, the file is what makes it *openable*,
    #: and one megabyte of PDF is a thousandth the price of the embeddings
    #: derived from it. Collapsing them would price a photo album like a
    #: library.
    file_bytes: int | None = 0


#: How long an answer is out before it comes back (2026-09-27 decision).
#:
#: Short on purpose. With each answer renewing on its own clock, the window
#: sets *how fast* answers return, and the weekly allowance still bounds the
#: month — so two hours rather than five costs nothing more at the ceiling
#: and turns "come back tonight" into "back in forty minutes".
ANSWER_WINDOW_HOURS = 2

#: Answers per window and per week. Measured against cost: one answer is
#: about ₹0.09 (3.1 Flash-Lite), so the weekly ceilings cap a month at ~₹8
#: (Free), ~₹60 (Standard) and ~₹161 (Premium) — 42–45% of what a paid plan
#: nets after GST and the store's cut, where 200 and 1,000 a day allowed
#: ₹564 and ₹2,808. A typical subscriber uses under a fifth of the week.
#: Searching is not metered at all: it runs on the phone.
FREE_ANSWERS = (2, 20)
STANDARD_ANSWERS = (10, 150)
PREMIUM_ANSWERS = (25, 400)

#: Kept-file allowances.
#:
#: Free gets a real but small amount rather than nothing: a vault that cannot
#: hand back a single file it was given is hard to trust, and 1 GiB is a few
#: hundred documents or a hundred photos — enough to learn what the product
#: does. Above the ceiling a capture is still indexed and still answers
#: questions; only the copy of the file is declined, and the memory says so.
#:
#: **Sized against cost (2026-09-27).** A kept gigabyte is about ₹2.5 a month
#: in Firebase Storage, and it never stops costing. The old 100 GB (Standard)
#: and 1 TB (Premium) came to ₹250 and ₹2,560 a month when full — the second
#: more than three times what Premium nets after GST and the store's cut.
#: 30 GB and 200 GB cap those at ~₹75 and ~₹500, while still being several
#: years of a typical user's captures (~50 MB a month). The originals also
#: stay on the phone, so a full allowance loses no one a file.
#:
#: **Cut again before launch (2026-10-14), with nobody paying yet.** 512 MB /
#: 5 GB / 15 GB cap a full allowance at ~₹1.25 / ₹12.5 / ₹37.5 a month, so a user
#: at every limit still nets above cost on both plans (Premium used to lose
#: ~₹350 a month when full). 5 GB is about 8 years of a typical user.
#: Accounts that already hold a snapshot keep the allowance they were given
#: (see `resolve`); new accounts and new purchases take these.
FREE_FILES = 512 * MIB
STANDARD_FILES = 5 * GIB
PREMIUM_FILES = 15 * GIB

ENTITLEMENTS: dict[str, Entitlements] = {
    FREE: Entitlements(FREE, 30, 0, 2 * GIB, 1, *FREE_ANSWERS, FREE_FILES),
    STANDARD: Entitlements(STANDARD, 365, 90, 32 * GIB, 3, *STANDARD_ANSWERS, STANDARD_FILES),
    PREMIUM: Entitlements(PREMIUM, None, None, 256 * GIB, None, *PREMIUM_ANSWERS, PREMIUM_FILES),
}


def reads_economy(tier: str) -> bool:
    """Whether this tier's files are read by the cheaper model.

    Free only. Reading is the largest cost a free user carries — about ₹9 of
    ₹14 a month on 3.6 Flash, since a transcript is output tokens — and on
    3.1 Flash-Lite it is about ₹4. Paid plans keep the fuller reader: an
    extraction is baked into the index for good, and they are paying for it.
    `readWith` on each memory records which model read it, so an upgrade can
    have its library read again.
    """
    return tier == FREE


def answers_upgradeable(tier: str) -> bool:
    """Whether paying would give this user more answers. Premium is the top:
    telling a Premium subscriber to upgrade would sell nothing."""
    return tier != PREMIUM


def plan_summaries() -> dict[str, dict]:
    """Every tier's entitlements, as the paywall prints them.

    Screen 1S lists what each plan includes. The design writes those lines
    out — "15 GB · 100 asks a month" — and they are not this product's
    numbers (Free is 2 GB of index and four asks a day). Sending the real
    table means the paywall prints what the backend will actually enforce,
    and a change to the table reaches the paywall with the deploy that makes
    it, instead of leaving an app build describing last month's plans.

    Answers are sent as both limits and the window's length, so the card
    can say "10 answers every 2 hours" in the backend's own numbers.
    """
    return {
        tier: {
            "memoryWindowDays": e.memory_window_days,
            "indexBytes": e.index_bytes,
            "fileBytes": e.file_bytes,
            "connectedAccounts": e.connected_accounts,
            "windowQueries": e.window_queries,
            "windowHours": ANSWER_WINDOW_HOURS,
            "weeklyQueries": e.weekly_queries,
        }
        for tier, e in ENTITLEMENTS.items()
    }


def entitlements_for(tier: str) -> Entitlements:
    return ENTITLEMENTS.get(tier, ENTITLEMENTS[FREE])


def snapshot_fields(e: Entitlements) -> dict:
    """The per-axis grants as a subscription document stores them.

    One list, used by every writer of a snapshot (`subscriptions.snapshot`,
    `user_lifecycle.FREE_TIER`), because a writer that forgets an axis is
    exactly how `fileBytes` went missing: no snapshot carried it, the
    dataclass default of 0 applied, and no user's file was ever kept.
    """
    return {
        "memoryWindowDays": e.memory_window_days,
        "backupWindowDays": e.backup_window_days,
        "indexBytes": e.index_bytes,
        "connectedAccounts": e.connected_accounts,
        "windowQueries": e.window_queries,
        "weeklyQueries": e.weekly_queries,
        "fileBytes": e.file_bytes,
    }


def _test_accounts() -> frozenset[str]:
    """Accounts granted the top tier without a purchase.

    Read from the environment rather than hardcoded, deliberately. A list of
    privileged identities baked into source is a backdoor that survives every
    review by looking like configuration; in `.env` it is visible in a diff,
    changeable without a code change, and obviously data.

    Accepts uids and email addresses so either works — a uid survives an
    email change, an email survives the account being recreated.

    The `testAccounts` collection in Firestore adds to this list, so an
    account can be added from the Firebase console without a deploy
    (`firestore_test_accounts`). Client access to that collection is denied outright
    in `firestore.rules`.
    """
    raw = os.environ.get("TEST_ACCOUNTS", "")
    from_env = frozenset(part.strip().lower() for part in raw.split(",") if part.strip())
    return from_env | firestore_test_accounts.listed()


def is_test_account(uid: str, *, email: str | None = None) -> bool:
    """Whether this identity is on the test-account list.

    Exposed so the profile screen can *say so*. A build that silently hands
    one address the top tier is the kind of thing that ships to production
    unnoticed; a badge on the account screen reading "test account" makes it
    impossible to forget which it is.
    """
    allowed = _test_accounts()
    if not allowed:
        return False
    return bool(({uid.lower(), (email or "").lower()} - {""}) & allowed)


def resolve_for_user(
    uid: str,
    subscription: dict | None,
    *,
    email: str | None = None,
    now: datetime | None = None,
) -> Entitlements:
    """What this user is entitled to, including the test-account override.

    The override is logged every time it applies. A privileged path that
    operates silently is one nobody notices has been left on — and this one
    hands out the most expensive tier in the product.
    """
    allowed = _test_accounts()
    if allowed:
        identity = {uid.lower(), (email or "").lower()} - {""}
        if identity & allowed:
            print(f"[knowra] test_account_entitlement uid={uid} tier={PREMIUM}")
            return ENTITLEMENTS[PREMIUM]

    return resolve(subscription, now=now)


def resolve(subscription: dict | None, *, now: datetime | None = None) -> Entitlements:
    """What this user is entitled to right now.

    Never raises — a billing problem must not be able to take the app down. An
    absent, lapsed or unreadable subscription resolves to Free.
    """
    if not subscription:
        return ENTITLEMENTS[FREE]

    moment = now or datetime.now(UTC)
    status = subscription.get("status", "active")

    if status not in {"active", "in_trial", "in_grace"}:
        return ENTITLEMENTS[FREE]

    if status == "in_grace":
        # A declined card must not read as data loss while the store is still
        # retrying the payment.
        grace_until = subscription.get("graceUntil")
        if grace_until and _as_datetime(grace_until) < moment:
            return ENTITLEMENTS[FREE]
    else:
        period_end = subscription.get("currentPeriodEnd")
        if period_end and _as_datetime(period_end) < moment:
            return ENTITLEMENTS[FREE]

    # The snapshot taken when the subscription began wins over the current
    # plan table: a later pricing change must not shrink an existing
    # subscriber's memory window, which would destroy data they paid to keep.
    if "memoryWindowDays" in subscription:
        table = entitlements_for(subscription.get("tier", FREE))
        return Entitlements(
            tier=subscription.get("tier", FREE),
            memory_window_days=subscription.get("memoryWindowDays"),
            backup_window_days=subscription.get("backupWindowDays"),
            index_bytes=subscription.get("indexBytes"),
            connected_accounts=subscription.get("connectedAccounts"),
            # Snapshots from before the window-and-week model carry
            # `dailyQueries` instead; like a missing `fileBytes`, a missing
            # axis takes the tier's current allowance rather than none.
            window_queries=subscription.get("windowQueries", table.window_queries),
            weekly_queries=subscription.get("weeklyQueries", table.weekly_queries),
            # Snapshots written before kept files existed have no `fileBytes`.
            # A missing axis is not a grant of zero: it takes the tier's
            # current allowance — the one thing a snapshot cannot have frozen.
            file_bytes=subscription.get("fileBytes", table.file_bytes),
        )

    return entitlements_for(subscription.get("tier", FREE))


def recall_expiry(captured_at: datetime, entitlements: Entitlements) -> datetime | None:
    """When a memory stops being searchable.

    Measured from capture, not from the subscription — so upgrading revives
    what you already have rather than only helping from here on. That is the
    difference between a paywall and a ransom.
    """
    days = entitlements.memory_window_days
    return None if days is None else captured_at + timedelta(days=days)


def _as_datetime(value: object) -> datetime:
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=UTC)
    # Firestore timestamps arrive as objects with .timestamp() in some paths.
    return datetime.fromtimestamp(float(value), tz=UTC)  # type: ignore[arg-type]
