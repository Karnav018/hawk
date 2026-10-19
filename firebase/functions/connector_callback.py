"""The https landing pad for provider OAuth redirects.

Google refuses a custom-scheme redirect URI on any client requesting restricted
scopes — `drive.readonly` is restricted, so `com.knowra.knowra://…` is rejected
outright at client-creation time. A provider that would accept a custom scheme
still comes through here: pointing only Google somewhere else would put a
per-provider, per-platform redirect table in the middle of a layer whose whole
purpose is not having one.

So every provider redirects here, over https, and this forwards to the app.

Deliberately the dumbest function in the codebase. It holds an authorization
code for the length of one 302 and makes no decision about it — validation
happens in `complete_connection`, which has the PKCE verifier. Logic here would
be attack surface on an endpoint that is, by necessity, public and
unauthenticated.
"""

from __future__ import annotations

from urllib.parse import urlencode

from firebase_functions import https_fn, options

#: Where the app is listening. Registered in AndroidManifest.xml and
#: Info.plist; the scheme, not the path, is what the OS matches on.
APP_REDIRECT = "com.knowra.knowra://oauth/callback"

#: Forwarded verbatim; everything else is dropped.
#:
#: A whitelist rather than a passthrough of `request.args`, so this can never
#: be steered into carrying attacker-chosen parameters into the app. Together
#: with the hard-coded destination that is what keeps it from being an open
#: redirector — the one thing a public endpoint like this must never become.
FORWARDED = ("code", "state", "error", "error_description", "scope")


@https_fn.on_request(
    region="us-central1",
    memory=options.MemoryOption.MB_128,
    max_instances=10,
)
def oauth_callback(req: https_fn.Request) -> https_fn.Response:
    params = {key: req.args[key] for key in FORWARDED if key in req.args}
    target = f"{APP_REDIRECT}?{urlencode(params)}" if params else APP_REDIRECT

    # A body as well as the header: a browser that declines to follow a 302
    # into a non-http scheme silently strands the user on a blank page
    # otherwise, with the connection half-finished and no way to say so.
    body = (
        "<!doctype html><meta charset=utf-8>"
        "<meta name=viewport content='width=device-width,initial-scale=1'>"
        f"<meta http-equiv=refresh content='0;url={target}'>"
        "<title>Returning to Knowra</title>"
        "<style>body{background:#070b16;color:#fff;font:15px/1.6 system-ui;"
        "display:grid;place-items:center;height:100vh;margin:0;text-align:center}"
        "a{color:#5b8cff}</style>"
        f"<div><p>Returning to Knowra…</p><p><a href='{target}'>Tap to continue</a></p></div>"
    )

    return https_fn.Response(
        body,
        status=302,
        headers={
            "Location": target,
            # The URL carries a live authorization code. Nothing may keep it.
            "Cache-Control": "no-store, no-cache, must-revalidate",
            "Referrer-Policy": "no-referrer",
            "Content-Type": "text/html; charset=utf-8",
        },
    )
