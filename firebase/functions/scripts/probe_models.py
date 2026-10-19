"""Which Gemini model ids will actually answer on this project's key.

`ListModels` is not the answer — it lists ids the API has, not ids this
project may call; a 2-series id was listed and still returned 404. The only
proof is a `generateContent` on each candidate, which is what this does, with
a one-word prompt and nothing printed but the id and the outcome.

Run from `firebase/functions`, with the key in the environment for this
process only:

    GEMINI_API_KEY="$(firebase functions:secrets:access GEMINI_API_KEY \
        --project knowra-506719)" venv/bin/python scripts/probe_models.py
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

API = "https://generativelanguage.googleapis.com/v1beta"
CANDIDATES = (
    "gemini-2.0-flash",
    "gemini-2.0-flash-lite",
    "gemini-2.5-flash",
    "gemini-2.5-flash-lite",
    "gemini-3.5-flash-lite",
    "gemini-3.6-flash",
    "gemini-flash-latest",
    "gemini-flash-lite-latest",
)


def probe(model: str, key: str) -> str:
    body = json.dumps(
        {
            "contents": [{"role": "user", "parts": [{"text": "Reply with the word ok."}]}],
            "generationConfig": {"maxOutputTokens": 5, "temperature": 0},
        }
    ).encode()
    request = urllib.request.Request(  # noqa: S310
        f"{API}/models/{model}:generateContent?key={key}",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        response = urllib.request.urlopen(request, timeout=60)  # noqa: S310
    except urllib.error.HTTPError as error:
        try:
            reason = json.loads(error.read()).get("error", {}).get("message", "")
        except (ValueError, AttributeError):
            reason = ""
        return f"{error.code} {reason[:90]}"
    except urllib.error.URLError as error:
        return f"unreachable ({error.reason})"
    with response:
        return f"{response.status} ok"


def main() -> int:
    key = os.environ.get("GEMINI_API_KEY", "").strip()
    if not key:
        print("GEMINI_API_KEY is not set for this process; see the docstring.", file=sys.stderr)
        return 2
    width = max(len(m) for m in CANDIDATES)
    for model in CANDIDATES:
        print(f"{model:<{width}}  {probe(model, key)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
