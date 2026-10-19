"""Callables for screens 3F, 3G and 3K.

Connections are entirely server-owned: `firestore.rules` denies every client
write to `storageAccounts`, so the only way to gain, narrow or drop access is
through one of these. That is what makes the free tier's one-account limit an
actual limit rather than a label on a button.
"""

from __future__ import annotations

import asyncio
from datetime import UTC, datetime

from firebase_admin import firestore
from firebase_functions import https_fn, options

import billing
import chunk_store
import connector_oauth as oauth
import device_vault
from connectors import (
    PROFILES,
    ConnectorError,
    ConnectorState,
    ProviderNotConfigured,
    ScopeLevel,
    connector_for,
    is_configured,
    profile_for,
    source_url,
)

ACCOUNTS = "storageAccounts"

#: Secrets each connector function needs at runtime.
#:
#: Only the providers this deployment has actually registered are listed.
#: Firebase refuses to deploy a function declaring a secret that does not
#: exist, so adding a provider means creating its secrets *and* adding them
#: here — until then `registry.is_configured` returns False and screen 3F
#: dims the row, which is the designed behaviour rather than a failure.
#:
#: CONNECTOR_KEY is not optional: `connector_oauth.seal` refuses to store a
#: refresh token without it.
# Adding a provider means creating its secrets AND listing them here —
# Firebase refuses to deploy a function declaring a secret that does not
# exist. A provider left off this list reports `configured: false` and screen
# 3F dims its row with a reason, which is the designed degradation rather
# than a failure.
PROVIDER_SECRETS = [
    "CONNECTOR_KEY",
    "GOOGLE_DRIVE_CLIENT_ID",
    "GOOGLE_DRIVE_CLIENT_SECRET",
]


def _uid(req: https_fn.CallableRequest) -> str:
    if req.auth is None or not req.auth.uid:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.UNAUTHENTICATED, "Sign in first.")
    return req.auth.uid


def _entitlements(uid: str, *, email: str | None = None) -> billing.Entitlements:
    db = firestore.client()
    doc = db.collection("users").document(uid).collection("subscription").document("current").get()
    return billing.resolve_for_user(uid, doc.to_dict() if doc.exists else None, email=email)


def _accounts_in_use(uid: str) -> list[dict]:
    """Accounts that count against the plan limit.

    Revoked accounts are excluded: the index they built survives revocation
    and a reconnect is one tap, but holding a slot for a connection that
    cannot sync would mean a revoked Drive blocks the user from connecting
    anything at all.

    So is the phone vault, for a different reason — see `device_vault`. The
    limit prices cloud connections, and a free user who picked their own
    phone on 3F would otherwise arrive at the Drive row already full.
    """
    db = firestore.client()
    return [
        {"id": doc.id, **(doc.to_dict() or {})}
        for doc in db.collection(ACCOUNTS).where("userId", "==", uid).stream()
        if (doc.to_dict() or {}).get("state") != ConnectorState.REVOKED
        and device_vault.counts_against_plan(doc.to_dict() or {})
    ]


def _enforce_account_limit(
    uid: str, entitlements: billing.Entitlements, *, excluding: str | None = None
) -> None:
    """Raise unless the caller has room for one more connection.

    Checked in **both** `begin_connection` and `complete_connection`, which is
    not redundancy. `begin_connection` checks so the user is told before being
    sent to Google — refusing them after they have authorised is a worse
    experience. `complete_connection` checks because the first check is not
    binding: nothing stops a client calling `begin_connection` twice, banking
    two valid challenges while under the limit, and redeeming both. Only the
    check at the moment the account row is written can actually hold the line.

    `excluding` is the account being re-connected, which already owns its slot.
    """
    limit = entitlements.connected_accounts
    if limit is None:
        return

    in_use = [a for a in _accounts_in_use(uid) if a["id"] != excluding]
    if len(in_use) < limit:
        return

    raise https_fn.HttpsError(
        https_fn.FunctionsErrorCode.RESOURCE_EXHAUSTED,
        f"Your plan connects {limit} account{'' if limit == 1 else 's'}. "
        "Upgrade to add another, or disconnect one first.",
        {"limit": limit, "used": len(in_use)},
    )


def _email_of(req: https_fn.CallableRequest) -> str | None:
    return (req.auth.token or {}).get("email") if req.auth else None


def _account(uid: str, account_id: str):
    """Fetch an account the caller actually owns.

    A missing document and someone else's document raise the identical error:
    distinguishing them turns this into an oracle for whether a given account
    id exists.
    """
    ref = firestore.client().collection(ACCOUNTS).document(account_id)
    snapshot = ref.get()
    data = snapshot.to_dict() if snapshot.exists else None
    if not data or data.get("userId") != uid:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.NOT_FOUND, "No such connection.")
    return ref, data


def _label(provider: object) -> object:
    """The provider's name, for a row that has to print one.

    Three cases and they are all reachable: a registered connector, the phone
    vault, and a provider that was removed from the product while somebody
    still had an account connected to it. The last one falls back to the raw
    id rather than crashing the screen that lists it.
    """
    if device_vault.is_device(provider):
        return device_vault.LABEL
    if provider in PROFILES:
        return PROFILES[str(provider)].label
    return provider


def _redact(account_id: str, data: dict) -> dict:
    """The account as the client is allowed to see it."""
    provider = data.get("provider")
    return {
        "id": account_id,
        "provider": provider,
        "label": _label(provider),
        # Which sort of source this is, so the app can tell a browser-consent
        # row from a file-picker one without naming a provider in the UI.
        "kind": device_vault.KIND if device_vault.is_device(provider) else device_vault.OAUTH_KIND,
        "email": data.get("email"),
        "displayName": data.get("displayName"),
        "state": data.get("state", ConnectorState.CONNECTED),
        "scopeLevel": data.get("scopeLevel", ScopeLevel.READ),
        "fileCount": data.get("fileCount", 0),
        "bytes": data.get("bytes", 0),
        "indexedFolders": data.get("indexedFolders", []),
        "connectedAt": _iso(data.get("connectedAt")),
        "lastSyncedAt": _iso(data.get("lastSyncedAt")),
        "error": data.get("error"),
    }


def _iso(value) -> str | None:
    return value.isoformat() if isinstance(value, datetime) else None


def _level(raw: object) -> ScopeLevel:
    try:
        return ScopeLevel(str(raw or ScopeLevel.READ))
    except ValueError:
        raise https_fn.HttpsError(
            https_fn.FunctionsErrorCode.INVALID_ARGUMENT, "Unknown permission level."
        ) from None


def _provider(raw: object) -> str:
    """The id of an OAuth provider, or a refusal.

    The phone vault is named separately rather than falling into "unknown
    storage provider": it is a real, offered source, and telling a client
    that the thing on its own screen does not exist sends whoever debugs it
    looking for a typo instead of for the right callable.
    """
    provider = str(raw or "")
    if device_vault.is_device(provider):
        raise https_fn.HttpsError(
            https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            "The phone vault does not connect through a browser — call connect_device_vault.",
        )
    if provider not in PROFILES:
        raise https_fn.HttpsError(
            https_fn.FunctionsErrorCode.INVALID_ARGUMENT, "Unknown storage provider."
        )
    return provider


def _reject_device(data: dict) -> None:
    """Guard the callables that only make sense against a provider.

    Reached only by a client calling the wrong one, but the failure it
    prevents is `connector_for("internal")` raising KeyError inside an async
    task — which surfaces as INTERNAL and says nothing about what went wrong.
    """
    if device_vault.is_device(data.get("provider")):
        raise https_fn.HttpsError(
            https_fn.FunctionsErrorCode.FAILED_PRECONDITION,
            "The phone vault has no folders to choose — files are picked on the device.",
        )


def _translate(error: ConnectorError) -> https_fn.HttpsError:
    if error.revoked:
        code = https_fn.FunctionsErrorCode.PERMISSION_DENIED
    elif error.retryable:
        code = https_fn.FunctionsErrorCode.UNAVAILABLE
    else:
        code = https_fn.FunctionsErrorCode.FAILED_PRECONDITION
    return https_fn.HttpsError(code, str(error))


# ----------------------------------------------------------------- catalogue


@https_fn.on_call(
    region="us-central1",
    memory=options.MemoryOption.MB_256,
    secrets=PROVIDER_SECRETS,
)
def list_connectors(req: https_fn.CallableRequest) -> dict:
    """What screen 3F renders: every source, and what is connected to it.

    Two kinds of row come back in one list. `kind: "oauth"` is a provider the
    user authorises in a browser; `kind: "device"` is the phone vault, whose
    files are picked through the OS. Sending both from here rather than
    hard-coding the second one in the app is what keeps 3F a list of sources
    instead of a list of connectors plus a special case.

    Providers this build has no credentials for come back `configured: false`
    rather than being filtered out — so a misconfigured release shows a
    disabled row with a reason instead of looking like the provider was never
    supported at all.
    """
    uid = _uid(req)
    entitlements = _entitlements(uid, email=_email_of(req))

    db = firestore.client()
    accounts = [
        _redact(doc.id, doc.to_dict() or {})
        for doc in db.collection(ACCOUNTS).where("userId", "==", uid).stream()
    ]
    # `used` is rendered against the plan limit, so it counts the same
    # things the limit does — which is cloud connections, not the phone.
    live = [
        a
        for a in accounts
        if a["state"] != ConnectorState.REVOKED and device_vault.counts_against_plan(a)
    ]

    return {
        "providers": [
            {
                "id": pid,
                "label": profile.label,
                "kind": device_vault.OAUTH_KIND,
                "configured": is_configured(pid),
            }
            for pid, profile in PROFILES.items()
        ]
        # The phone vault is last because the design puts the cloud options
        # first: someone who wants their Drive indexed should not have to
        # read past the device they are holding to find it.
        + [device_vault.descriptor()],
        "accounts": accounts,
        "limit": entitlements.connected_accounts,
        "used": len(live),
        "canConnectMore": entitlements.connected_accounts is None
        or len(live) < entitlements.connected_accounts,
    }


@https_fn.on_call(region="us-central1", memory=options.MemoryOption.MB_256)
def connect_device_vault(req: https_fn.CallableRequest) -> dict:
    """Choose this phone as a source. Screen 3F's second option.

    No OAuth, no plan check, no index job. The user has already granted file
    access to the OS, the files are picked one at a time through the system
    picker, and each one reaches the pipeline as an ordinary capture — so
    everything this has to do is make the choice durable and visible.

    Idempotent, and therefore safe as the double-tap target it will be: the
    row has a deterministic id, so a second call updates the first row rather
    than listing the same phone twice.
    """
    uid = _uid(req)
    account_id, data = device_vault.connect(uid, device_name=req.data.get("deviceName"))
    return {"account": _redact(account_id, data)}


# --------------------------------------------------------------- connecting


@https_fn.on_call(
    region="us-central1",
    memory=options.MemoryOption.MB_256,
    secrets=PROVIDER_SECRETS,
)
def begin_connection(req: https_fn.CallableRequest) -> dict:
    """Step one of screen 3F: hand back a URL for the app to open.

    The quota is checked *here*, before the user is sent to Google, rather
    than after they come back — making somebody authorise an account we are
    then going to refuse is a worse experience than telling them first.
    """
    uid = _uid(req)
    provider = _provider(req.data.get("provider"))
    level = _level(req.data.get("scopeLevel"))
    entitlements = _entitlements(uid, email=_email_of(req))

    # Early, so the user is told before being sent to the provider. Not
    # binding — see `_enforce_account_limit`.
    _enforce_account_limit(uid, entitlements)

    try:
        return oauth.begin(uid, provider, level)
    except ProviderNotConfigured as error:
        raise https_fn.HttpsError(
            https_fn.FunctionsErrorCode.FAILED_PRECONDITION,
            f"{profile_for(provider).label} is not available in this build.",
            {"reason": str(error)},
        ) from error


@https_fn.on_call(
    region="us-central1",
    memory=options.MemoryOption.MB_256,
    timeout_sec=120,
    secrets=PROVIDER_SECRETS,
)
def complete_connection(req: https_fn.CallableRequest) -> dict:
    """Step two: the code comes back, the grant is stored, the account exists.

    Idempotent on `providerAccountId`: reconnecting the same Google account
    updates the existing row instead of creating a second one that would eat
    another slot of the user's quota.

    A reconnect also revives the index — see `_revive`. `disconnect_account`
    promises in as many words that reconnecting restores the memories it
    parked, and until this was here nothing kept that promise.
    """
    uid = _uid(req)
    challenge_id = str(req.data.get("challengeId") or "")
    code = str(req.data.get("code") or "")
    state = str(req.data.get("state") or "")

    if not challenge_id or not code or not state:
        raise https_fn.HttpsError(
            https_fn.FunctionsErrorCode.INVALID_ARGUMENT, "Incomplete callback."
        )

    try:
        challenge = oauth.claim(uid, challenge_id, state)
    except oauth.ChallengeError as error:
        raise https_fn.HttpsError(
            https_fn.FunctionsErrorCode.PERMISSION_DENIED, str(error)
        ) from error

    provider = challenge["provider"]
    level = _level(challenge.get("scopeLevel"))
    connector = connector_for(provider)

    async def _connect():
        from connectors import REDIRECT_URI

        tokens = await connector.exchange_code(code, challenge["verifier"], REDIRECT_URI)
        return tokens, await connector.get_account(tokens.access_token)

    try:
        tokens, identity = asyncio.run(_connect())
    except ConnectorError as error:
        raise _translate(error) from error

    db = firestore.client()
    now = datetime.now(UTC)

    match = [
        doc
        for doc in db.collection(ACCOUNTS)
        .where("userId", "==", uid)
        .where("provider", "==", provider)
        .where("providerAccountId", "==", identity.account_id)
        .limit(1)
        .stream()
    ]
    ref = match[0].reference if match else db.collection(ACCOUNTS).document()
    reconnected = bool(match)

    # The binding check. A reconnect is exempt because it already holds its
    # slot; a genuinely new account has to fit.
    _enforce_account_limit(uid, _entitlements(uid), excluding=ref.id if reconnected else None)

    ref.set(
        {
            "userId": uid,
            "provider": provider,
            "providerAccountId": identity.account_id,
            "email": identity.email,
            "displayName": identity.display_name,
            "state": ConnectorState.CONNECTED,
            "scopeLevel": str(level),
            "grantedScopes": list(tokens.granted_scopes),
            "connectedAt": now,
            "updatedAt": now,
            "error": None,
            # A reconnect keeps the folder selection and the index; the point
            # of REVOKED being its own state is that the work survives it.
            **({} if reconnected else {"indexedFolders": [], "fileCount": 0, "bytes": 0}),
        },
        merge=True,
    )
    oauth.store_tokens(ref, tokens, account_id=ref.id)

    # The half of "reconnect" that was missing. Without it the row came back
    # CONNECTED over an index that stayed dormant, so a reconnected Drive
    # answered nothing and read as an empty vault.
    revived = _revive(db, uid, ref.id) if reconnected else 0

    return {
        "account": _redact(ref.id, (ref.get().to_dict() or {})),
        "reconnected": reconnected,
        "revived": revived,
    }


def still_in_window(data: dict, now: datetime) -> bool:
    """Whether this memory's plan window is still open.

    A memory can be dormant for two unrelated reasons — the source was
    disconnected, or the plan's retention window closed over it — and only
    the first is undone by reconnecting. Reviving on `sourceAvailable` alone
    would hand a free account a year of history back through a disconnect and
    a reconnect, which is a paid feature reachable by two taps.
    """
    expires = data.get("recallExpiresAt")
    return not (isinstance(expires, datetime) and expires <= now)


def _revive(db, uid: str, account_id: str) -> int:
    """Undo what `disconnect_account` did to this account's memories.

    Keyed on `sourceAvailable == False`, which nothing but the disconnect
    sets — retention demotes by `recallState` alone, so the two reasons a
    memory can be dormant stay distinguishable here.

    Chunks are kept through a disconnect, so reviving is a state flip, not a
    re-index — but the flip has to reach the chunks: the phone's index and
    the server's passage lookup read the chunk's `recallState`, not the
    memory's. That is the whole point of REVOKED being a state rather than a
    deletion.
    """
    now = datetime.now(UTC)
    query = (
        db.collection("memories")
        .where("userId", "==", uid)
        .where("storageAccountId", "==", account_id)
        .where("sourceAvailable", "==", False)
    )

    docs = list(query.stream())
    back = [doc.id for doc in docs if still_in_window(doc.to_dict() or {}, now)]
    # Chunks first: a failure here leaves the memories untouched and the
    # reconnect retryable, rather than memories that say active over chunks
    # that are not.
    chunk_store.set_recall_state(db, back, "active")
    back_ids = set(back)

    revived = 0
    batch = db.batch()
    pending = 0
    for doc in docs:
        update = {"sourceAvailable": True, "updatedAt": now}
        if doc.id in back_ids:
            update["recallState"] = "active"
            update["chunkRecall"] = "active"
        batch.update(doc.reference, update)
        revived += 1
        pending += 1
        if pending == 450:
            batch.commit()
            batch = db.batch()
            pending = 0
    if pending:
        batch.commit()
    return revived


# -------------------------------------------------------------- permissions


@https_fn.on_call(
    region="us-central1",
    memory=options.MemoryOption.MB_256,
    secrets=PROVIDER_SECRETS,
)
def set_scope_level(req: https_fn.CallableRequest) -> dict:
    """Screen 3G's second toggle.

    Escalating cannot be done server-side — only the user can widen a grant —
    so this returns another authorization URL and the app runs the same
    browser round trip. Narrowing is immediate: we drop the tokens and force a
    reconnect at READ, because there is no partial-revoke API anywhere and
    keeping a manage-capable token while the toggle reads "off" would make the
    switch a lie.
    """
    uid = _uid(req)
    account_id = str(req.data.get("accountId") or "")
    level = _level(req.data.get("scopeLevel"))
    ref, data = _account(uid, account_id)

    current = _level(data.get("scopeLevel"))
    if current is level:
        return {"changed": False, "account": _redact(account_id, data)}

    if level is ScopeLevel.MANAGE:
        return {
            "changed": False,
            "consentRequired": True,
            **oauth.begin(uid, data["provider"], level),
        }

    # Revoke FIRST, while the grant is still readable.
    #
    # The obvious order — drop our copy, then tell the provider — cannot work:
    # `_revoke_quietly` needs the access token to call the revoke endpoint, and
    # it reads that token from the document. Deleting first made the revoke a
    # guaranteed no-op that failed silently, so the user turned "manage
    # storage" off, the UI said it was off, and Google still held a
    # write-capable grant. A switch that lies about permissions is worse than
    # no switch.
    asyncio.run(_revoke_quietly(data["provider"], ref, account_id))

    ref.update(
        {
            "scopeLevel": str(ScopeLevel.READ),
            "state": ConnectorState.REVOKED,
            "grantedScopes": [],
            "updatedAt": datetime.now(UTC),
        }
    )
    ref.collection("private").document("oauth").delete()

    return {"changed": True, "reconnectRequired": True}


async def _revoke_quietly(provider: str, ref, account_id: str) -> None:
    """Tell the provider to forget us; never fail the caller if it will not.

    The local grant is already gone by the time this runs, so a provider that
    is down means a token we cannot use is still listed on someone's account
    page — untidy, not dangerous.
    """
    # Not merely nothing to do: `connector_for("internal")` is a KeyError,
    # and the bare `except` below would swallow it into a disconnect that
    # looks like it revoked something. There was never a grant.
    if device_vault.is_device(provider):
        return

    try:
        token = await oauth.access_token(ref, account_id=account_id, provider=provider)
        await connector_for(provider).revoke(token)
    except Exception:
        return


# ------------------------------------------------------------------ folders


@https_fn.on_call(
    region="us-central1",
    memory=options.MemoryOption.MB_512,
    timeout_sec=180,
    secrets=PROVIDER_SECRETS,
)
def list_provider_folders(req: https_fn.CallableRequest) -> dict:
    """Screen 3K's list, with the counts it displays."""
    uid = _uid(req)
    account_id = str(req.data.get("accountId") or "")
    parent_id = req.data.get("parentId")
    ref, data = _account(uid, account_id)
    _reject_device(data)
    provider = data["provider"]

    async def _list():
        token = await oauth.access_token(ref, account_id=account_id, provider=provider)
        return await connector_for(provider).list_folders(token, parent_id=parent_id)

    try:
        folders = asyncio.run(_list())
    except ConnectorError as error:
        if error.revoked:
            _mark_revoked(ref)
        raise _translate(error) from error

    return {
        "folders": [
            {
                "id": f.id,
                "name": f.name,
                "path": f.path,
                "fileCount": f.file_count,
                "bytes": f.bytes,
            }
            for f in sorted(folders, key=lambda f: f.file_count, reverse=True)
        ],
        "selected": [f["id"] for f in data.get("indexedFolders", [])],
    }


@https_fn.on_call(region="us-central1", memory=options.MemoryOption.MB_256)
def set_indexed_folders(req: https_fn.CallableRequest) -> dict:
    """3K → 3L. Records the scope, then queues the first index.

    The folder metadata is stored alongside the ids so screen 3L can show
    "Reading 508 files" without going back to the provider for numbers it was
    just told.
    """
    uid = _uid(req)
    account_id = str(req.data.get("accountId") or "")
    raw = req.data.get("folders")
    if not isinstance(raw, list):
        raise https_fn.HttpsError(
            https_fn.FunctionsErrorCode.INVALID_ARGUMENT, "Pick at least one folder."
        )

    ref, data = _account(uid, account_id)
    _reject_device(data)
    folders = [
        {
            "id": str(f.get("id")),
            "name": str(f.get("name", "")),
            "path": str(f.get("path", "")),
            "fileCount": int(f.get("fileCount") or 0),
            "bytes": int(f.get("bytes") or 0),
        }
        for f in raw
        if isinstance(f, dict) and f.get("id")
    ]
    if not folders:
        raise https_fn.HttpsError(
            https_fn.FunctionsErrorCode.INVALID_ARGUMENT, "Pick at least one folder."
        )

    now = datetime.now(UTC)
    total_files = sum(f["fileCount"] for f in folders)
    total_bytes = sum(f["bytes"] for f in folders)

    ref.update(
        {
            "indexedFolders": folders,
            "fileCount": total_files,
            "bytes": total_bytes,
            "state": ConnectorState.SYNCING,
            "updatedAt": now,
        }
    )

    db = firestore.client()
    job = db.collection("indexJobs").document()
    job.set(
        {
            "userId": uid,
            "accountId": account_id,
            "provider": data["provider"],
            "state": "queued",
            "folders": folders,
            "totals": {"files": total_files, "bytes": total_bytes},
            "progress": {"discovered": 0, "processed": 0, "failed": 0},
            "stage": None,
            "createdAt": now,
            "updatedAt": now,
        }
    )

    return {"jobId": job.id, "files": total_files, "bytes": total_bytes}


# -------------------------------------------------------------- disconnect


@https_fn.on_call(
    region="us-central1",
    memory=options.MemoryOption.MB_256,
    timeout_sec=120,
    secrets=PROVIDER_SECRETS,
)
def disconnect_account(req: https_fn.CallableRequest) -> dict:
    """§40's fork, made explicit.

    `deleteMemories: false` — the default — keeps the index and marks the
    memories unreachable, so reconnecting restores them. Deletion is the
    destructive branch and has to be asked for by name.

    Disconnecting the **phone vault** touches no memories at all, and that is
    correct rather than an oversight: a capture carries no `storageAccountId`
    (see `device_vault.owns_memory`) so the loop below matches none of them,
    and the files behind them live in Knowra's own file vault, not on the
    phone. Unlisting the device as a source must not make everything ever
    captured on it stop answering questions.
    """
    uid = _uid(req)
    account_id = str(req.data.get("accountId") or "")
    delete_memories = bool(req.data.get("deleteMemories"))
    ref, data = _account(uid, account_id)

    asyncio.run(_revoke_quietly(data["provider"], ref, account_id))
    ref.collection("private").document("oauth").delete()

    db = firestore.client()
    memories = (
        db.collection("memories")
        .where("userId", "==", uid)
        .where("storageAccountId", "==", account_id)
    )

    docs = list(memories.stream())
    if not delete_memories:
        # The chunks go dormant with their memories, first — otherwise every
        # phone keeps finding files from an account that is gone.
        chunk_store.set_recall_state(db, [doc.id for doc in docs], "dormant")

    touched = 0
    batch = db.batch()
    pending = 0
    for doc in docs:
        if delete_memories:
            batch.delete(doc.reference)
        else:
            # §39's "mark source unavailable": the row and its pointer stay,
            # so a reconnect is a status flip rather than a re-index.
            batch.update(
                doc.reference,
                {"sourceAvailable": False, "recallState": "dormant", "chunkRecall": "dormant"},
            )
        touched += 1
        pending += 1
        if pending == 450:
            batch.commit()
            batch = db.batch()
            pending = 0
    if pending:
        batch.commit()

    if delete_memories:
        ref.delete()
    elif device_vault.is_device(data.get("provider")):
        device_vault.pause(ref)
    else:
        _mark_revoked(ref)

    return {"memoriesAffected": touched, "deleted": delete_memories}


@https_fn.on_call(region="us-central1", memory=options.MemoryOption.MB_256)
def complete_storage_setup(req: https_fn.CallableRequest) -> dict:
    """Ends the onboarding run — including screen 3F's "Skip" path.

    Skipping is a real choice, not a deferral: device-only capture is a usable
    product, and a user who never connects cloud storage must not be parked on
    the connect screen forever.
    """
    uid = _uid(req)
    now = datetime.now(UTC)
    # set(merge=True), not update(): update() raises NotFound on a document
    # that does not exist, and the profile is not guaranteed to. The blocking
    # `before_user_created` trigger that seeds it only runs on projects with
    # Identity Platform enabled — without it the document is created by the
    # client at screen 3J, and any path that reaches here first would fail on
    # an update.
    firestore.client().collection("users").document(uid).set(
        {"userId": uid, "storageSetupAt": now, "updatedAt": now}, merge=True
    )
    return {"storageSetupAt": now.isoformat()}


def _mark_revoked(ref) -> None:
    ref.update(
        {
            "state": ConnectorState.REVOKED,
            "updatedAt": datetime.now(UTC),
            "error": {
                "code": "revoked",
                "message": "Access was revoked at the provider.",
            },
        }
    )


# ------------------------------------------------------------ single files


#: One page of files on screen 1L. Small on purpose: the screen shows a list
#: somebody scrolls, and each page costs a provider round trip plus the index
#: lookups below.
FILE_PAGE = 30


@https_fn.on_call(
    region="us-central1",
    memory=options.MemoryOption.MB_512,
    timeout_sec=120,
    secrets=PROVIDER_SECRETS,
)
def list_provider_files(req: https_fn.CallableRequest) -> dict:
    """Screen 1L's file list, each row marked indexed or not.

    The index state is the point of the screen: v2 could only tell you which
    *folders* were selected, so a file inside a chosen folder that the
    pipeline had skipped — wrong type, too large, still queued — was
    indistinguishable from one it had read. Here every row says which it is,
    and offers the button that changes it.

    **The two counts are account-wide, not page-wide.** The header prints
    "842 OF 10,412 INDEXED", and a client holding thirty rows cannot derive
    either number. Both are cheap: the total is the figure the folder
    selection already wrote to the account, and the indexed count is a
    Firestore aggregation, billed by index entries read rather than by
    document.

    Paged by the provider's own opaque token rather than by offset, because a
    file added mid-scroll shifts every offset below it and the user would see
    a row twice or not at all.
    """
    uid = _uid(req)
    account_id = str(req.data.get("accountId") or "")
    ref, data = _account(uid, account_id)
    _reject_device(data)
    provider = data["provider"]

    # The folders the user actually chose. Listing the whole drive would be a
    # different screen — this one is "the files you brought".
    folders = [f for f in data.get("indexedFolders", []) if f.get("id")]
    folder_id = str(req.data.get("folderId") or (folders[0]["id"] if folders else "root"))
    page_token = req.data.get("pageToken")

    async def _list():
        token = await oauth.access_token(ref, account_id=account_id, provider=provider)
        return await connector_for(provider).list_files(
            token, folder_id=folder_id, page_token=page_token
        )

    try:
        page = asyncio.run(_list())
    except ConnectorError as error:
        if error.revoked:
            _mark_revoked(ref)
        raise _translate(error) from error

    files = page.files[:FILE_PAGE]
    indexed = _indexed_refs(uid, account_id, [f.id for f in files])
    label = _breadcrumb(profile_for(provider).label, folders, folder_id)

    return {
        "files": [
            {
                "id": f.id,
                "name": f.name,
                # Pre-joined for display. The provider's folder chain, not a
                # filesystem path — the client renders it, it does not parse
                # it.
                "path": label,
                "mimeType": f.mime_type,
                "bytes": f.bytes,
                "indexed": f.id in indexed,
            }
            for f in files
        ],
        "nextPageToken": page.cursor or None,
        "indexedCount": _indexed_total(uid, account_id),
        "totalCount": int(data.get("fileCount") or 0),
    }


def _breadcrumb(provider_label: str, folders: list[dict], folder_id: str) -> str:
    """ "Drive › Contracts", from what the account already knows.

    Built from the stored folder selection rather than by walking the
    provider's parent chain: the names were captured when the user picked the
    folders, and re-fetching them to render a caption would be a round trip
    per page for a string that has not changed.
    """
    name = next(
        (f.get("name") for f in folders if f.get("id") == folder_id and f.get("name")),
        None,
    )
    short = provider_label.replace("Google ", "")
    return f"{short} › {name}" if name else short


def _indexed_total(uid: str, account_id: str) -> int:
    """How many of this account's files have a memory. Account-wide."""
    try:
        result = (
            firestore.client()
            .collection("memories")
            .where("userId", "==", uid)
            .where("storageAccountId", "==", account_id)
            .count()
            .get()
        )
        return int(result[0][0].value)
    except Exception:
        # A count that fails is a missing number in a header, not a reason to
        # fail the screen the list is on.
        return 0


def _indexed_refs(uid: str, account_id: str, file_ids: list[str]) -> set[str]:
    """Which of these provider file ids already have a memory.

    Chunked at 30 because that is Firestore's ceiling on an `in` filter, and
    a page of 30 files must not become 30 document reads.
    """
    if not file_ids:
        return set()

    db = firestore.client()
    found: set[str] = set()
    for start in range(0, len(file_ids), 30):
        batch = file_ids[start : start + 30]
        query = (
            db.collection("memories")
            .where("userId", "==", uid)
            .where("storageAccountId", "==", account_id)
            .where("sourceRef", "in", batch)
            .select(["sourceRef"])
        )
        for doc in query.stream():
            ref = (doc.to_dict() or {}).get("sourceRef")
            if ref:
                found.add(str(ref))
    return found


@https_fn.on_call(
    region="us-central1",
    memory=options.MemoryOption.MB_512,
    timeout_sec=120,
    secrets=PROVIDER_SECRETS,
)
def set_file_indexed(req: https_fn.CallableRequest) -> dict:
    """Index one provider file, or drop its index. Screen 1L's row button.

    **Un-indexing never touches the provider's file.** It deletes the memory
    and, through the existing triggers, the chunks and the kept copy — the
    derived layer, which is the only thing this product made. The spec is
    explicit that a user can remove what Hawk knows about a file without
    removing the file, and this is where that promise is kept.

    Indexing writes a memory document and stops. The `on_memory_created`
    trigger does the rest, exactly as it does for a capture or a folder
    sweep — one pipeline, three entry points.
    """
    uid = _uid(req)
    account_id = str(req.data.get("accountId") or "")
    file_id = str(req.data.get("fileId") or "")
    indexed = bool(req.data.get("indexed"))

    if not file_id:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.INVALID_ARGUMENT, "Which file?")

    ref, data = _account(uid, account_id)
    _reject_device(data)
    provider = data["provider"]
    db = firestore.client()

    existing = [
        doc
        for doc in db.collection("memories")
        .where("userId", "==", uid)
        .where("storageAccountId", "==", account_id)
        .where("sourceRef", "==", file_id)
        .limit(1)
        .stream()
    ]

    if not indexed:
        for doc in existing:
            doc.reference.delete()
        return {"indexed": False, "removed": len(existing)}

    # Already indexed is a success, not a conflict: the button is a state, and
    # a double tap must not create a second memory for one file.
    if existing:
        return {"indexed": True, "memoryId": existing[0].id, "created": False}

    async def _read():
        token = await oauth.access_token(ref, account_id=account_id, provider=provider)
        return await connector_for(provider).get_file(token, file_id=file_id)

    try:
        f = asyncio.run(_read())
    except ConnectorError as error:
        if error.revoked:
            _mark_revoked(ref)
        raise _translate(error) from error

    now = datetime.now(UTC)
    memory = db.collection("memories").document()
    memory.set(
        {
            "userId": uid,
            "title": f.name,
            "type": _memory_type(f.mime_type),
            "status": "uploaded",
            "recallState": "active",
            "storageAccountId": account_id,
            "provider": provider,
            # §10 — a pointer, never a copy. The original stays where the
            # user already keeps it.
            "sourceRef": f.id,
            "sourceUrl": source_url(provider, f.id),
            "sourceAvailable": True,
            "mimeType": f.mime_type,
            "bytes": f.bytes,
            "contentHash": f.content_hash,
            "capturedAt": f.modified_at or now,
            "createdAt": now,
            "updatedAt": now,
        }
    )
    return {"indexed": True, "memoryId": memory.id, "created": True}


def _memory_type(mime: str) -> str:
    """The library's own type for a file, from its mime type.

    Deliberately coarse. The library draws one icon per type and the pipeline
    branches on the mime type itself, so a finer taxonomy here would be a
    second source of truth for a decision neither of them makes.
    """
    if mime.startswith("image/"):
        return "photo"
    if mime.startswith("audio/"):
        return "audio"
    if mime.startswith("video/"):
        return "video"
    return "document"
