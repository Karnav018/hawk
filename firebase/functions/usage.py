"""Answer metering — a rolling two-hour window, and a week.

Two limits, one job each:

* **The window.** A plan's answers per two hours, and each answer comes back
  two hours after it was used, *on its own clock*. Nothing resets all at
  once: the app can always say when the next one returns ("back at 3:12
  pm"), and no burst across a boundary can fit two windows into a minute.
* **The week.** The cost cap — what bounds a month. It ends at Monday 00:00
  in the user's own zone, and that moment is **recorded when the week's
  first answer is taken**, never recomputed per request: a client that
  flipped its offset across Monday midnight could otherwise reset its week
  as often as it liked.

What is metered is an **answer**. Searching runs on the phone and costs
nothing, so it is never counted, and an answer that cited nothing is handed
back (see [counts_as_ask]).

Reserve, then settle. The slot is taken in a transaction *before* the model
runs, so two questions sent together can never both take the last one — the
old check-then-count let exactly that through — and it is released if the
answer does not count or the request fails. Server-side and non-negotiable:
a client-side counter is a suggestion.

The rules live in [Ledger] and [standing], which touch no database; the
Firestore calls below only load, apply and store them.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta, tzinfo

from firebase_admin import firestore
from firebase_functions import https_fn

import billing
from billing import Entitlements

WINDOW = timedelta(hours=billing.ANSWER_WINDOW_HOURS)

#: `users/{uid}/usage/{LEDGER}` — one document per user.
LEDGER = "answers"


def _parse(raw: object) -> datetime | None:
    if isinstance(raw, datetime):
        return raw if raw.tzinfo else raw.replace(tzinfo=UTC)
    if isinstance(raw, str):
        try:
            parsed = datetime.fromisoformat(raw)
        except ValueError:
            return None
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=UTC)
    return None


def next_monday(now: datetime, zone: tzinfo) -> datetime:
    """The next Monday 00:00 in [zone], as a UTC instant."""
    local = now.astimezone(zone)
    days = (7 - local.weekday()) % 7 or 7
    midnight = (local + timedelta(days=days)).replace(hour=0, minute=0, second=0, microsecond=0)
    return midnight.astimezone(UTC)


@dataclass(frozen=True, slots=True)
class Ledger:
    """What one user has spent, as of a moment."""

    #: When each answer still inside the window was taken, oldest first.
    stamps: tuple[datetime, ...] = ()
    #: Answers taken since the week began.
    week_count: int = 0
    #: When the week ends. None until its first answer is taken.
    week_ends_at: datetime | None = None

    @classmethod
    def read(cls, data: dict | None, now: datetime) -> Ledger:
        """The stored document as of [now]: stale stamps dropped, an ended
        week started over."""
        data = data or {}
        stamps = sorted(
            stamp
            for stamp in (_parse(raw) for raw in data.get("stamps") or [])
            if stamp is not None and now - stamp < WINDOW
        )
        ends = _parse(data.get("weekEndsAt"))
        count = int(data.get("weekCount") or 0)
        if ends is None or now >= ends:
            count, ends = 0, None
        return cls(stamps=tuple(stamps), week_count=count, week_ends_at=ends)

    def to_doc(self, now: datetime) -> dict:
        # ISO strings, not timestamps: a reservation is matched back by exact
        # value, and a string round-trips exactly where a timestamp may not.
        return {
            "stamps": [stamp.isoformat() for stamp in self.stamps],
            "weekCount": self.week_count,
            "weekEndsAt": self.week_ends_at.isoformat() if self.week_ends_at else None,
            "updatedAt": now,
        }


@dataclass(frozen=True, slots=True)
class Standing:
    """Both allowances, as the app and the refusal describe them."""

    window_limit: int | None
    window_used: int
    #: When the oldest answer in the window comes back. None when the window
    #: holds nothing.
    window_next_at: datetime | None
    week_limit: int | None
    week_used: int
    week_resets_at: datetime

    @property
    def window_remaining(self) -> int | None:
        return None if self.window_limit is None else max(0, self.window_limit - self.window_used)

    @property
    def week_remaining(self) -> int | None:
        return None if self.week_limit is None else max(0, self.week_limit - self.week_used)

    @property
    def spent(self) -> str | None:
        """Which limit stops the next answer — the one that frees *later*,
        since that is when asking actually becomes possible again."""
        week = self.week_remaining == 0
        window = self.window_remaining == 0
        if week and window and self.window_next_at is not None:
            return "week" if self.week_resets_at >= self.window_next_at else "window"
        if week:
            return "week"
        if window:
            return "window"
        return None

    @property
    def available_at(self) -> datetime | None:
        match self.spent:
            case "week":
                return self.week_resets_at
            case "window":
                return self.window_next_at
            case _:
                return None

    def report(self) -> dict:
        remaining = [r for r in (self.window_remaining, self.week_remaining) if r is not None]
        return {
            "window": {
                "limit": self.window_limit,
                "used": self.window_used,
                "remaining": self.window_remaining,
                "hours": billing.ANSWER_WINDOW_HOURS,
                "nextAt": self.window_next_at.isoformat() if self.window_next_at else None,
            },
            "week": {
                "limit": self.week_limit,
                "used": self.week_used,
                "remaining": self.week_remaining,
                "resetsAt": self.week_resets_at.isoformat(),
            },
            "remaining": min(remaining) if remaining else None,
            "spent": self.spent,
            "availableAt": self.available_at.isoformat() if self.available_at else None,
        }


def standing(ledger: Ledger, entitlements: Entitlements, now: datetime, zone: tzinfo) -> Standing:
    return Standing(
        window_limit=entitlements.window_queries,
        window_used=len(ledger.stamps),
        window_next_at=ledger.stamps[0] + WINDOW if ledger.stamps else None,
        week_limit=entitlements.weekly_queries,
        week_used=ledger.week_count,
        week_resets_at=ledger.week_ends_at or next_monday(now, zone),
    )


@dataclass(frozen=True, slots=True)
class Reservation:
    """A slot taken before answering — what [release] needs to hand it back."""

    stamp: datetime
    week_ends_at: datetime
    #: The allowance with this slot taken, for the response.
    report: dict


class Spent(Exception):
    """Both allowances are spent — a state, not a failure."""

    def __init__(self, standing: Standing):
        super().__init__(standing.spent)
        self.standing = standing


def take(
    ledger: Ledger, entitlements: Entitlements, now: datetime, zone: tzinfo
) -> tuple[Ledger, Reservation]:
    """One slot out of both allowances, or [Spent]."""
    before = standing(ledger, entitlements, now, zone)
    if before.spent:
        raise Spent(before)
    ends = ledger.week_ends_at or next_monday(now, zone)
    taken = Ledger(
        stamps=(*ledger.stamps, now),
        week_count=ledger.week_count + 1,
        week_ends_at=ends,
    )
    return taken, Reservation(
        stamp=now,
        week_ends_at=ends,
        report=standing(taken, entitlements, now, zone).report(),
    )


def give_back(ledger: Ledger, reservation: Reservation) -> Ledger:
    """Undo one [take]. A stamp that has aged out has nothing left to return
    to the window; a week that has ended has nothing left to return to."""
    stamps = list(ledger.stamps)
    if reservation.stamp in stamps:
        stamps.remove(reservation.stamp)
    same_week = ledger.week_ends_at == reservation.week_ends_at
    return Ledger(
        stamps=tuple(stamps),
        week_count=max(0, ledger.week_count - 1) if same_week else ledger.week_count,
        week_ends_at=ledger.week_ends_at,
    )


def counts_as_ask(*, answered: bool, cited: int) -> bool:
    """Whether a question keeps the slot it reserved.

    **Only a question that found something.** An answer written from the
    user's own files, with at least one citation, is what the allowance
    exists to meter. Everything else is handed back:

    * "Nothing in your library matches" — the vault did not have it, and
      charging for that would bill the user for our miss.
    * A stray tap on the eye that sent a scrap of noise — it retrieves the
      nearest passages (vector search always returns *something*), the model
      reads them, finds nothing that answers "uh", and says so. Without this
      rule every accidental touch spent an ask.

    Searching was never metered; see `api.search`.
    """
    return answered and cited > 0


def _clock(moment: datetime, zone: tzinfo) -> str:
    """3:12 pm, in the user's zone."""
    local = moment.astimezone(zone)
    hour = local.hour % 12 or 12
    return f"{hour}:{local.minute:02d} {'am' if local.hour < 12 else 'pm'}"


def exhausted(entitlements: Entitlements, standing: Standing, zone: tzinfo) -> https_fn.HttpsError:
    """The refusal — which limit, when it frees, and whether paying helps.

    Premium has nothing to upgrade to, so its sentence offers the wait and a
    way to get in touch instead of a button that sells nothing.
    """
    upgradeable = billing.answers_upgradeable(entitlements.tier)
    which = standing.spent
    at = standing.available_at
    if which == "week":
        limit = standing.week_limit
        message = f"That's all {limit} answers this week. They reset on Monday." + (
            " Upgrade for more." if upgradeable else " Get in touch if you need more."
        )
    else:
        limit = standing.window_limit
        back = f" The next one is back at {_clock(at, zone)}." if at else ""
        message = f"That's your {limit} answers for now.{back}" + (
            " Upgrade for more." if upgradeable else ""
        )
    return https_fn.HttpsError(
        https_fn.FunctionsErrorCode.RESOURCE_EXHAUSTED,
        message,
        {
            "which": which,
            "limit": limit,
            "resetsAt": at.isoformat() if at else None,
            "upgradeable": upgradeable,
        },
    )


# ---------------------------------------------------------------- Firestore


def _ref(uid: str):
    return firestore.client().collection("users").document(uid).collection("usage").document(LEDGER)


def peek(uid: str, entitlements: Entitlements, *, zone: tzinfo = UTC) -> dict:
    """Both allowances, without spending anything."""
    now = datetime.now(UTC)
    snapshot = _ref(uid).get()
    ledger = Ledger.read(snapshot.to_dict() if snapshot.exists else None, now)
    return standing(ledger, entitlements, now, zone).report()


def reserve(uid: str, entitlements: Entitlements, *, zone: tzinfo = UTC) -> Reservation:
    """Take one slot before answering, or raise the refusal."""
    db = firestore.client()
    ref = _ref(uid)

    @firestore.transactional
    def _take(transaction) -> Reservation:  # type: ignore[no-untyped-def]
        now = datetime.now(UTC)
        snapshot = ref.get(transaction=transaction)
        ledger = Ledger.read(snapshot.to_dict() if snapshot.exists else None, now)
        taken, reservation = take(ledger, entitlements, now, zone)
        transaction.set(ref, taken.to_doc(now))
        return reservation

    try:
        return _take(db.transaction())
    except Spent as spent:
        raise exhausted(entitlements, spent.standing, zone) from None


def release(
    uid: str, entitlements: Entitlements, reservation: Reservation, *, zone: tzinfo = UTC
) -> dict | None:
    """Hand a reserved slot back. Returns the allowance after, or None.

    Best effort, and never raises: the answer is already written, and failing
    the request over a refund would throw it away. A release that does not
    land costs the user one answer, which the window returns in two hours.
    """
    db = firestore.client()
    ref = _ref(uid)

    @firestore.transactional
    def _give(transaction) -> dict:  # type: ignore[no-untyped-def]
        now = datetime.now(UTC)
        snapshot = ref.get(transaction=transaction)
        ledger = give_back(
            Ledger.read(snapshot.to_dict() if snapshot.exists else None, now), reservation
        )
        transaction.set(ref, ledger.to_doc(now))
        return standing(ledger, entitlements, now, zone).report()

    try:
        return _give(db.transaction())
    except Exception as error:  # a refund must never fail the request
        print(f"[knowra] usage_release_failed uid={uid} error={error!r}"[:300])
        return None
