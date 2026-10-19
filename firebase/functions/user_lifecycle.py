"""What happens the first time someone signs in.

Runs regardless of *how* they signed in — Apple, Google or an email code — so
there is one place that decides what a new account starts with, rather than
three sign-in paths each remembering to do it.

Seeded through **two** entry points, because the better one is not always
available:

* `on_user_created` — a blocking `beforeUserCreated` trigger. The account does
  not exist until it has run, so the client cannot win a race against it. But
  blocking triggers require Identity Platform; on a plain Firebase Auth project
  the deploy reports *"Blocking Functions may only be configured for GCIP
  projects"*, the function deploys, and Firebase Auth never calls it.
* `ensure_profile` — a callable the app invokes when it observes that its own
  profile document is missing. Slower and racier by construction, but it works
  on any project.

Both delegate to `seed`, which is idempotent: whichever runs first wins and the
other is a no-op. Keeping the blocking trigger means enabling Identity Platform
later is a switch, not a migration.
"""

from datetime import UTC, datetime

from firebase_admin import firestore
from firebase_functions import https_fn, identity_fn, options

import billing

#: Free tier, straight from the plan table — every axis, so a snapshot seeded
#: here can never lack one (see `billing.snapshot_fields`).
FREE_TIER = {
    "tier": billing.FREE,
    "status": "active",
    **billing.snapshot_fields(billing.entitlements_for(billing.FREE)),
}


def seed(uid: str, *, email: str | None, name: str | None) -> bool:
    """Create the profile and its entitlements. Idempotent.

    Returns True if this call did the seeding, False if it was already done.

    Every write is `merge=True` and guarded on absence, so the second caller
    cannot clobber the first — which matters because the two entry points can
    genuinely overlap: a user signing in on a project that later enables
    Identity Platform has both paths live at once.
    """
    db = firestore.client()
    now = datetime.now(UTC)

    profile = db.collection("users").document(uid)
    existing = profile.get()

    # Never overwrite a profile that already exists — `name` and
    # `inputPreference` are the user's answers on screen 3J, and re-seeding
    # after a token refresh would silently reset them.
    if not existing.exists:
        profile.set(
            {
                "userId": uid,
                "email": email,
                "name": name,
                # Voice is the product's default, per screen 3J.
                "inputPreference": "voice",
                # Null until screen 3J is completed. The client routes on this,
                # so it must exist as a field rather than be absent.
                "onboardedAt": None,
                # Null until screens 3F-3L are completed or skipped.
                "storageSetupAt": None,
                "usedBytes": 0,
                "createdAt": now,
                "updatedAt": now,
            }
        )
    else:
        # A profile created by the client at 3J carries only what the rules let
        # it write. Backfill the server-owned fields without touching theirs.
        data = existing.to_dict() or {}
        missing = {
            key: value
            for key, value in (
                ("userId", uid),
                ("email", email),
                ("usedBytes", 0),
                ("createdAt", now),
            )
            if data.get(key) is None
        }
        if missing:
            profile.set({**missing, "updatedAt": now}, merge=True)

    subscription = profile.collection("subscription").document("current")
    if subscription.get().exists:
        return False

    subscription.set({**FREE_TIER, "createdAt": now, "updatedAt": now})
    return True


@https_fn.on_call(region="us-central1", memory=options.MemoryOption.MB_256)
def ensure_profile(req: https_fn.CallableRequest) -> dict:
    """Seed on demand, for projects without Identity Platform.

    The client calls this only when its profile snapshot comes back missing —
    so on a project where the blocking trigger *is* registered, this is never
    reached and costs nothing.

    Deliberately takes no arguments. Identity comes from `req.auth`, so a
    caller cannot seed, or reshape, somebody else's account.
    """
    if req.auth is None or not req.auth.uid:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.UNAUTHENTICATED, "Sign in first.")

    token = req.auth.token or {}
    seeded = seed(
        req.auth.uid,
        email=token.get("email"),
        name=token.get("name"),
    )
    return {"seeded": seeded}


@identity_fn.before_user_created(region="us-central1", memory=options.MemoryOption.MB_256)
def on_user_created(
    event: identity_fn.AuthBlockingEvent,
) -> identity_fn.BeforeCreateResponse | None:
    """Seed the profile and entitlements as the account is created.

    A blocking trigger rather than a background one: with `onCreate` the client
    can win the race and read a user document that does not exist yet, which
    shows an empty library to someone who just signed up. Blocking means the
    account does not exist until this has run.

    Only actually invoked on projects with Identity Platform enabled — see the
    module docstring. `ensure_profile` is the fallback everywhere else.
    """
    user = event.data
    seed(user.uid, email=user.email, name=user.display_name)
    return None
