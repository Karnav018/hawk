"""How many calls a minute this key really gets, per model — by trying.

Fires a burst of tiny requests at each model with a thread pool and tallies
the status codes. A 429 inside the first few dozen means a free-tier-sized
allowance; none across the burst means the allowance is at least the burst.
Costs a few cents. Same key handling as `probe_models.py`.

    GEMINI_API_KEY="$(firebase functions:secrets:access GEMINI_API_KEY \
        --project knowra-506719)" venv/bin/python scripts/probe_burst.py
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request
from collections import Counter
from concurrent.futures import ThreadPoolExecutor

API = "https://generativelanguage.googleapis.com/v1beta"
#: (model, requests, parallelism)
PLAN = (
    ("gemini-3.5-flash-lite", 120, 20),
    ("gemini-3.6-flash", 60, 15),
    ("gemini-embedding-001", 120, 20),
)


def _call(model: str, key: str) -> tuple[int, str]:
    if "embedding" in model:
        url = f"{API}/models/{model}:embedContent?key={key}"
        body = {"content": {"parts": [{"text": "lease deposit"}]}, "outputDimensionality": 8}
    else:
        url = f"{API}/models/{model}:generateContent?key={key}"
        body = {
            "contents": [{"role": "user", "parts": [{"text": "Reply with the word ok."}]}],
            "generationConfig": {"maxOutputTokens": 5, "temperature": 0},
        }
    request = urllib.request.Request(  # noqa: S310
        url,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        response = urllib.request.urlopen(request, timeout=60)  # noqa: S310
    except urllib.error.HTTPError as error:
        return error.code, error.headers.get("retry-after", "")
    except urllib.error.URLError:
        return 0, ""
    with response:
        return response.status, ""


def _burst(model: str, count: int, parallel: int, key: str) -> str:
    started = time.perf_counter()
    with ThreadPoolExecutor(max_workers=parallel) as pool:
        results = list(pool.map(lambda _: _call(model, key), range(count)))
    elapsed = time.perf_counter() - started
    statuses = Counter(status for status, _ in results)
    limited = [(i, ra) for i, (status, ra) in enumerate(results) if status == 429]
    line = f"{model:<24} {count} calls in {elapsed:5.1f}s  " + "  ".join(
        f"{s}:{n}" for s, n in sorted(statuses.items())
    )
    if limited:
        line += f"  first 429 at #{limited[0][0] + 1}"
        waits = sorted({ra for _, ra in limited if ra})
        if waits:
            line += f"  retry-after={waits}"
    return line


def main() -> int:
    key = os.environ.get("GEMINI_API_KEY", "").strip()
    if not key:
        print("GEMINI_API_KEY is not set for this process; see the docstring.", file=sys.stderr)
        return 2
    for model, count, parallel in PLAN:
        print(_burst(model, count, parallel, key))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
