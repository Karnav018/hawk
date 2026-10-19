"""Google Drive.

The reference connector: it is the one we have credentials for, and the other
two are shaped to match it.

Drive has no folder type — a folder is a file whose mime type is
`application/vnd.google-apps.folder` — and no per-folder size. Both are hidden
here so screen 3K can render "412 FILES · 8.2 GB" without knowing any of it.
"""

from __future__ import annotations

from datetime import datetime

from .base import (
    GOOGLE_DRIVE,
    ChangeSet,
    ConnectorError,
    OAuthTokens,
    ProviderAccount,
    ProviderFile,
    ProviderFolder,
    ProviderProfile,
    ScopeLevel,
)
from .http import client, raise_for, tokens_from

FOLDER_MIME = "application/vnd.google-apps.folder"

#: Google Workspace formats have no bytes to download — they are exported.
#: Excluded from the first index because the export path is a separate piece
#: of work, and silently indexing an empty byte stream would look like a bug.
NATIVE_PREFIX = "application/vnd.google-apps."

API = "https://www.googleapis.com/drive/v3"

#: `open?id=` rather than `file/d/<id>/view`: the latter is a file viewer,
#: while `open` routes a Google Doc to Docs and a Sheet to Sheets as well as
#: showing a PDF — so one form is right for every item type. On a phone it is
#: also the link the Drive app registers for, so it opens there rather than
#: in a browser tab.
WEB_URL = "https://drive.google.com/open?id={id}"

PROFILE = ProviderProfile(
    id=GOOGLE_DRIVE,
    label="Google Drive",
    authorize_url="https://accounts.google.com/o/oauth2/v2/auth",
    token_url="https://oauth2.googleapis.com/token",  # noqa: S106 — a URL, not a secret
    revoke_url="https://oauth2.googleapis.com/revoke",
    scopes={
        # drive.readonly, not drive: §46 says never request delete permission
        # for a user who only wants search.
        ScopeLevel.READ: (
            "https://www.googleapis.com/auth/drive.readonly",
            "https://www.googleapis.com/auth/userinfo.email",
        ),
        # drive.file would be narrower but only covers files *we* created,
        # which is the exact opposite of BYOS.
        ScopeLevel.MANAGE: ("https://www.googleapis.com/auth/drive",),
    },
    authorize_params={
        # Without access_type=offline Google issues no refresh token, and the
        # connection dies silently one hour after it is made.
        "access_type": "offline",
        # Forces the consent screen even on re-connect. Google only returns a
        # refresh token on the *first* grant, so a user who reconnects after
        # we lost their token would otherwise get an access token we cannot
        # renew.
        "prompt": "consent",
        # Incremental auth: escalating to MANAGE keeps the READ grant.
        "include_granted_scopes": "true",
    },
    file_url_template=WEB_URL,
)


def web_url(file_id: str) -> str:
    """The link that opens a Drive item in Drive, derived from its id alone.

    Kept as a named function because it reads better at a call site that
    already knows it is talking about Drive; the template it formats is the
    one on `PROFILE`, so there is still only one definition of the link.
    """
    return WEB_URL.format(id=file_id)


class GoogleDriveConnector:
    profile = PROFILE

    def __init__(self, client_id: str, client_secret: str):
        self._client_id = client_id
        self._client_secret = client_secret

    # ---------------------------------------------------------------- oauth

    async def exchange_code(self, code: str, verifier: str, redirect_uri: str) -> OAuthTokens:
        async with client() as http:
            response = await http.post(
                PROFILE.token_url,
                data={
                    "code": code,
                    "client_id": self._client_id,
                    "client_secret": self._client_secret,
                    "redirect_uri": redirect_uri,
                    "grant_type": "authorization_code",
                    "code_verifier": verifier,
                },
            )
        raise_for(response, what="Connecting Google Drive")
        tokens = tokens_from(response.json())

        if tokens.refresh_token is None:
            # Better to fail the connection than to store a grant that stops
            # working in an hour and reports itself as healthy until then.
            raise ConnectorError(
                "Google did not return a refresh token. Remove Vault from "
                "your Google account permissions and connect again."
            )
        return tokens

    async def refresh(self, refresh_token: str) -> OAuthTokens:
        async with client() as http:
            response = await http.post(
                PROFILE.token_url,
                data={
                    "refresh_token": refresh_token,
                    "client_id": self._client_id,
                    "client_secret": self._client_secret,
                    "grant_type": "refresh_token",
                },
            )
        raise_for(response, what="Renewing Google Drive access")
        return tokens_from(response.json())

    async def revoke(self, token: str) -> None:
        async with client() as http:
            # A token that is already dead is the outcome we wanted; only a
            # transport failure is worth reporting.
            await http.post(PROFILE.revoke_url or "", data={"token": token})

    async def get_account(self, access_token: str) -> ProviderAccount:
        async with client() as http:
            response = await http.get(
                f"{API}/about",
                params={"fields": "user(permissionId,emailAddress,displayName)"},
                headers=_auth(access_token),
            )
        raise_for(response, what="Reading your Google account")
        user = response.json().get("user", {})
        return ProviderAccount(
            account_id=user.get("permissionId", ""),
            email=user.get("emailAddress"),
            display_name=user.get("displayName"),
        )

    # -------------------------------------------------------------- listing

    async def list_folders(
        self, access_token: str, *, parent_id: str | None = None
    ) -> list[ProviderFolder]:
        """Top-level folders, with the counts screen 3K displays.

        Only one level deep on purpose. A full tree of a 10,000-file Drive is
        several minutes of paging for a screen that asks a coarse question,
        and 3K's own copy sets the expectation: "Pick folders now, add more
        later."
        """
        parent = parent_id or "root"
        query = f"'{parent}' in parents and mimeType = '{FOLDER_MIME}' and trashed = false"
        folders: list[ProviderFolder] = []
        page: str | None = None

        async with client() as http:
            while True:
                response = await http.get(
                    f"{API}/files",
                    params=_page_params(query, page, "files(id,name)"),
                    headers=_auth(access_token),
                )
                raise_for(response, what="Listing your Drive folders")
                body = response.json()
                folders += [
                    ProviderFolder(id=f["id"], name=f["name"], path=f["name"], parent_id=parent)
                    for f in body.get("files", [])
                ]
                page = body.get("nextPageToken")
                if not page:
                    break

            # Counts are a second pass because Drive cannot aggregate. Done
            # concurrently: sequentially this is one round trip per folder and
            # screen 3K would sit on a spinner.
            import asyncio

            sized = await asyncio.gather(
                *(self._measure(http, access_token, f) for f in folders),
                return_exceptions=True,
            )

        # A folder we could not measure still gets offered — it shows without
        # counts rather than vanishing from a list the user is choosing from.
        return [
            result if isinstance(result, ProviderFolder) else original
            for original, result in zip(folders, sized, strict=True)
        ]

    async def _measure(self, http, access_token: str, folder: ProviderFolder) -> ProviderFolder:
        count = 0
        total = 0
        page: str | None = None
        query = f"'{folder.id}' in parents and trashed = false"

        while True:
            response = await http.get(
                f"{API}/files",
                params=_page_params(query, page, "files(id,size,mimeType)"),
                headers=_auth(access_token),
            )
            raise_for(response, what="Measuring a Drive folder")
            body = response.json()
            for f in body.get("files", []):
                if f.get("mimeType") == FOLDER_MIME:
                    continue
                count += 1
                total += int(f.get("size") or 0)
            page = body.get("nextPageToken")
            if not page:
                break

        return ProviderFolder(
            id=folder.id,
            name=folder.name,
            path=folder.path,
            parent_id=folder.parent_id,
            file_count=count,
            bytes=total,
        )

    async def list_files(
        self, access_token: str, *, folder_id: str, page_token: str | None = None
    ) -> ChangeSet:
        query = f"'{folder_id}' in parents and trashed = false"
        async with client() as http:
            response = await http.get(
                f"{API}/files",
                params=_page_params(
                    query,
                    page_token,
                    "files(id,name,mimeType,size,modifiedTime,sha256Checksum,parents)",
                ),
                headers=_auth(access_token),
            )
        raise_for(response, what="Listing your Drive files")
        body = response.json()
        return ChangeSet(
            files=tuple(_file(f) for f in body.get("files", []) if _is_indexable(f)),
            cursor=body.get("nextPageToken") or "",
            has_more=bool(body.get("nextPageToken")),
        )

    async def get_file(self, access_token: str, *, file_id: str) -> ProviderFile:
        """One file's metadata, by id.

        Exists for indexing a single file on demand — screen 1L offers an
        Index button per row, and the alternative to this call is trusting
        the client's copy of the name, size and mime type. Those decide what
        the pipeline does with the bytes and what the plan is charged for, so
        they are re-read from the provider rather than accepted from a
        caller who could have edited them.
        """
        async with client() as http:
            response = await http.get(
                f"{API}/files/{file_id}",
                params={
                    "fields": "id,name,mimeType,size,modifiedTime,sha256Checksum,parents,trashed",
                    "supportsAllDrives": "true",
                },
                headers=_auth(access_token),
            )
        raise_for(response, what="Reading that Drive file")
        body = response.json()
        if body.get("trashed"):
            raise ConnectorError("That file is in the Drive bin.")
        if not _is_indexable(body):
            raise ConnectorError("That file type cannot be indexed yet.")
        return _file(body)

    async def get_changes(self, access_token: str, *, cursor: str | None) -> ChangeSet:
        """§39 — Drive's changes feed.

        With no cursor we ask Drive for one rather than replaying history: the
        caller wants "what changed since now", and the alternative is walking
        the entire change log of the account.
        """
        async with client() as http:
            if cursor is None:
                start = await http.get(f"{API}/changes/startPageToken", headers=_auth(access_token))
                raise_for(start, what="Starting Drive sync")
                return ChangeSet(files=(), cursor=start.json()["startPageToken"])

            response = await http.get(
                f"{API}/changes",
                params={
                    "pageToken": cursor,
                    "pageSize": 200,
                    "fields": (
                        "nextPageToken,newStartPageToken,"
                        "changes(removed,fileId,file(id,name,mimeType,size,"
                        "modifiedTime,sha256Checksum,parents))"
                    ),
                },
                headers=_auth(access_token),
            )
        raise_for(response, what="Syncing Google Drive")
        body = response.json()

        files: list[ProviderFile] = []
        for change in body.get("changes", []):
            if change.get("removed"):
                files.append(
                    ProviderFile(
                        id=change["fileId"],
                        name="",
                        mime_type="",
                        bytes=0,
                        deleted=True,
                    )
                )
            elif (f := change.get("file")) and _is_indexable(f):
                files.append(_file(f))

        next_page = body.get("nextPageToken")
        return ChangeSet(
            files=tuple(files),
            # newStartPageToken appears only on the last page; storing the
            # intermediate nextPageToken as if it were final would replay the
            # same changes forever.
            cursor=next_page or body.get("newStartPageToken", cursor),
            has_more=bool(next_page),
        )

    # ------------------------------------------------------------- contents

    async def download_file(self, access_token: str, *, file_id: str) -> bytes:
        async with client() as http:
            response = await http.get(
                f"{API}/files/{file_id}",
                params={"alt": "media"},
                headers=_auth(access_token),
            )
        raise_for(response, what="Downloading a file")
        return response.content

    async def delete_file(self, access_token: str, *, file_id: str) -> None:
        """§36 — only ever reached after an explicit, per-file confirmation."""
        async with client() as http:
            response = await http.post(f"{API}/files/{file_id}/trash", headers=_auth(access_token))
        raise_for(response, what="Moving a file to the trash")

    async def move_file(self, access_token: str, *, file_id: str, to_folder_id: str) -> None:
        async with client() as http:
            current = await http.get(
                f"{API}/files/{file_id}",
                params={"fields": "parents"},
                headers=_auth(access_token),
            )
            raise_for(current, what="Moving a file")
            parents = ",".join(current.json().get("parents", []))
            response = await http.patch(
                f"{API}/files/{file_id}",
                params={"addParents": to_folder_id, "removeParents": parents},
                headers=_auth(access_token),
            )
        raise_for(response, what="Moving a file")


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _page_params(query: str, page: str | None, fields: str) -> dict[str, str | int]:
    params: dict[str, str | int] = {
        "q": query,
        "pageSize": 200,
        "fields": f"nextPageToken,{fields}",
        # Shared drives are part of "your storage" to the person using them.
        "supportsAllDrives": "true",
        "includeItemsFromAllDrives": "true",
    }
    if page:
        params["pageToken"] = page
    return params


def _is_indexable(f: dict) -> bool:
    mime = f.get("mimeType", "")
    return mime != FOLDER_MIME and not mime.startswith(NATIVE_PREFIX)


def _file(f: dict) -> ProviderFile:
    parents = f.get("parents") or []
    return ProviderFile(
        id=f["id"],
        name=f.get("name", ""),
        mime_type=f.get("mimeType", ""),
        bytes=int(f.get("size") or 0),
        modified_at=_moment(f.get("modifiedTime")),
        content_hash=f.get("sha256Checksum"),
        parent_id=parents[0] if parents else None,
    )


def _moment(raw: str | None) -> datetime | None:
    if not raw:
        return None
    return datetime.fromisoformat(raw.replace("Z", "+00:00"))
