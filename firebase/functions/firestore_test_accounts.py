"""Test accounts listed in Firestore, so they can be added from the console.

`billing` grants Premium to any identity on the test-account list, and the
list has two sources:

* the `TEST_ACCOUNTS` line in `.env`, which only changes with a deploy;
* the `testAccounts` collection: one document per account, its ID the email
  address or the uid. Added and removed in the Firebase console, and live
  within `TTL_SECONDS` of the change.

Read at most once per `TTL_SECONDS` per instance. The list is consulted on
every entitlement check, and a database read on each of those would cost more
than the feature is worth.

Never raises. A failed read keeps the last list that was read, or none at
all: it must never take a request down, and never widen who gets Premium.
"""

from __future__ import annotations

import os
import time

COLLECTION = "testAccounts"
TTL_SECONDS = 60

#: When the list was last read, and what it held. Module-level on purpose:
#: one cache per instance, shared by every request that instance serves.
_state: dict = {"at": None, "ids": frozenset()}


def _deployed() -> bool:
    """Whether this process runs as a deployed or emulated function.

    Cloud Run sets K_SERVICE; the Functions emulator sets FUNCTIONS_EMULATOR.
    Unit tests and scripts on a developer machine have neither, and must never
    reach a real database just to work out someone's plan.
    """
    return bool(os.environ.get("K_SERVICE") or os.environ.get("FUNCTIONS_EMULATOR"))


def _fetch() -> frozenset[str]:
    from firebase_admin import firestore

    docs = firestore.client().collection(COLLECTION).stream()
    return frozenset(doc.id.strip().lower() for doc in docs if doc.id.strip())


def listed(*, now: float | None = None) -> frozenset[str]:
    """The ids and emails in the `testAccounts` collection, lowercased."""
    if not _deployed():
        return frozenset()

    moment = time.monotonic() if now is None else now
    last = _state["at"]
    if last is not None and moment - last < TTL_SECONDS:
        return _state["ids"]

    try:
        ids = _fetch()
    except Exception as error:
        print(f"[knowra] test_accounts_read_failed {error}")
        ids = _state["ids"]

    _state["at"], _state["ids"] = moment, ids
    return ids
