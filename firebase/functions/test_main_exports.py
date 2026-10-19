"""Every Cloud Function defined anywhere is exported by main.py.

The CLI deploys what it finds in `main`'s namespace and nothing else.
`embed_texts` and `purge_cloud_embeddings` were written, tested and never
deployed, because nothing had added them to `main.py`'s import list — and no
test noticed, because none imported `main`.
"""

from __future__ import annotations

import importlib
from pathlib import Path

import main

ROOT = Path(__file__).parent

#: The blocking auth trigger, kept out of main.py on purpose — see the
#: comment there.
EXCEPTED = {"on_user_created"}


def _defined() -> list[tuple[str, str]]:
    found: list[tuple[str, str]] = []
    for path in sorted(ROOT.glob("*.py")):
        if path.name.startswith("test_") or path.stem == "main":
            continue
        module = importlib.import_module(path.stem)
        for name, value in vars(module).items():
            if (
                hasattr(value, "__firebase_endpoint__")
                and getattr(value, "__module__", None) == module.__name__
            ):
                found.append((module.__name__, name))
    return found


def test_every_defined_function_is_exported():
    defined = _defined()
    assert defined, "no endpoints found — is ROOT right?"
    exported = {n for n, v in vars(main).items() if hasattr(v, "__firebase_endpoint__")}
    missing = sorted(
        f"{module}.{name}"
        for module, name in defined
        if name not in exported and name not in EXCEPTED
    )
    assert not missing, "defined but never deployed: " + ", ".join(missing)
