"""The scheduled Drive sync, as far as the app's "found N new files" goes.

`sync_connected_accounts` is the one thing Hawk does without being asked,
and the app announces what it added (`Snack.assistant`). It can only do that
if the sync says what it added — these pin that it does, and that a quiet
sync says nothing.
"""

from __future__ import annotations

import asyncio
from datetime import datetime

import pytest

import connector_sync
from connectors.base import ChangeSet, ProviderFile


class _Query:
    def __init__(self, found):
        self._found = found

    def where(self, *_):
        return self

    def limit(self, _):
        return self

    def stream(self):
        return iter(self._found)


class _Batch:
    def __init__(self, db):
        self._db = db

    def set(self, ref, data):
        self._db.created.append(data)

    def update(self, ref, data):
        self._db.updated.append(data)

    def commit(self):
        pass


class _Db:
    def __init__(self):
        self.created: list[dict] = []
        self.updated: list[dict] = []

    def collection(self, _):
        return self

    def document(self, *_):
        return object()

    # Querying `memories` for an existing row: none exist in these tests.
    def where(self, *_):
        return _Query([])

    def batch(self):
        return _Batch(self)


class _Ref:
    def __init__(self):
        self.updates: list[dict] = []

    def update(self, data):
        self.updates.append(data)


class _Connector:
    def __init__(self, files):
        self._files = files

    async def get_changes(self, token, *, cursor):
        return ChangeSet(files=self._files, cursor="next")


def _file(name, parent="chosen"):
    return ProviderFile(
        id=name,
        name=name,
        mime_type="application/pdf",
        bytes=10,
        modified_at=datetime(2026, 9, 27),
        parent_id=parent,
    )


@pytest.fixture
def run(monkeypatch):
    async def _token(*_, **__):
        return "token"

    monkeypatch.setattr(connector_sync.oauth, "access_token", _token)

    def _run(files):
        monkeypatch.setattr(connector_sync, "connector_for", lambda _: _Connector(files))
        db, ref = _Db(), _Ref()
        data = {
            "provider": "google_drive",
            "userId": "u1",
            "indexedFolders": [{"id": "chosen"}],
        }
        asyncio.run(connector_sync._sync_one(db, ref, "acc", data))
        return db, ref.updates[-1]

    return _run


def test_new_files_in_a_chosen_folder_are_counted(run):
    db, update = run([_file("a.pdf"), _file("b.pdf"), _file("c.pdf")])
    assert len(db.created) == 3
    assert update["lastSyncAdded"] == 3
    assert update["lastSyncAddedAt"] == update["lastSyncedAt"]


def test_files_outside_the_chosen_folders_are_not(run):
    db, update = run([_file("a.pdf"), _file("elsewhere.pdf", parent="other")])
    assert len(db.created) == 1
    assert update["lastSyncAdded"] == 1


def test_a_quiet_sync_says_nothing(run):
    # No new files: the last announcement's timestamp must survive, or the
    # app would re-raise it — or, worse, clear a count it never showed.
    _, update = run([])
    assert "lastSyncAdded" not in update
    assert "lastSyncAddedAt" not in update
    assert update["syncCursor"] == "next"
