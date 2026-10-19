"""Reading the page behind a saved link — the "ARCHIVED" the capture tile promises.

Until this existed a saved link was indexed by its title and the url string
and nothing else, so *"the pricing page I saved last month"* could only be
found by someone who already remembered what the page was called. A link
whose content is not read is a bookmark, and the product's claim is that you
can ask for things in your own words.

Fetching a URL the user supplied means this server makes a request to an
address the user chose, which is the classic SSRF shape — inside a Cloud
Functions VPC, where `169.254.169.254` hands out service-account tokens to
anyone who asks. Four guards, all load-bearing:

* **Scheme allowlist.** `file://`, `gopher://` and friends are not links.
* **Address check before every request.** Private, loopback, link-local and
  reserved ranges are refused, whether written as a literal or arrived at
  through DNS.
* **Every redirect hop re-checked.** A public host that 302s to the metadata
  server is the whole attack, so redirects are followed by hand rather than
  by `follow_redirects=True`, which would check only the first URL.
* **Bounded body and time.** A response is read to a ceiling and abandoned;
  an endpoint that streams forever must not hold a function instance.

What remains, and is worth naming rather than implying: the address is
resolved here and resolved again by the client, so a name that answers
differently between the two calls — DNS rebinding — is not closed by this.
Closing it means pinning the connection to the address that was checked,
which httpx will not do without a custom transport. The guard below is the
standard mitigation; the gap is real and small, and it is documented here so
the next person meets it in the source rather than in an incident.
"""

from __future__ import annotations

import html as html_module
import ipaddress
import re
import socket
from urllib.parse import urlparse

import httpx

#: Enough of a page to answer questions about it, and little enough that a
#: hostile response cannot fill a function's memory. Long articles are
#: chunk-capped downstream anyway (`ingestion.MAX_CHUNKS`).
MAX_BYTES = 2 * 1024 * 1024

MAX_REDIRECTS = 5

#: Shorter than the connector timeout. A user is waiting on the first index
#: of something they just saved, and a slow page is not worth 20 seconds of
#: a function instance.
TIMEOUT = httpx.Timeout(10.0, connect=5.0)

ALLOWED_SCHEMES = frozenset({"http", "https"})

#: Content types worth reading as text. A PDF behind a link would be better
#: served by the file route than by this one, and that is a separate piece of
#: work rather than a silent half-implementation.
READABLE = ("text/html", "text/plain", "application/xhtml+xml", "application/xml")

#: Sent because a bare client gets a consent wall or a 403 from a good share
#: of the web. Honest about what it is: a crawler with a name someone could
#: block deliberately beats one pretending to be Chrome.
HEADERS = {
    "User-Agent": "KnowraBot/1.0 (+https://knowra.app/bot) link-archiver",
    "Accept": "text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.1",
    "Accept-Language": "en",
}

_SCRIPT = re.compile(r"<(script|style|noscript|template)\b[^>]*>.*?</\1>", re.I | re.S)
_TITLE = re.compile(r"<title\b[^>]*>(.*?)</title>", re.I | re.S)
_TAG = re.compile(r"<[^>]+>")
_SPACE = re.compile(r"[ \t\r\f\v]+")
_BLANK = re.compile(r"\n\s*\n\s*")


class Unreachable(RuntimeError):
    """The link cannot be read, and the message says why in the user's terms.

    Not a reason to fail the capture: a link that could not be fetched — a
    dead domain, a timeout, a page that is not HTML — is still a link the
    user chose to keep, and it stays in the library indexed by its title and
    url exactly as it was before this module existed. [Blocked] is the one
    exception.
    """


class Blocked(Unreachable):
    """The page answered, and refused to be read — a login or a paywall.

    Unlike a dead link this is a verdict about the page, not the moment: it
    will refuse again tomorrow, and the memory it would leave is a url with
    nothing behind it. So the capture fails, with the one thing that helps —
    the page can still be kept as a PDF — in the words the app shows.
    """


#: Statuses that mean "you may not read this" rather than "this is broken".
#: 402 is the paywall code the few sites that use it mean literally.
BLOCKED_STATUSES = frozenset({401, 402, 403, 451})

#: What the app says about a blocked page (`Hawk Snackbars.dc.html`,
#: capture_page · error). Written once, here, because the app shows the
#: memory's error verbatim.
BLOCKED_MESSAGE = "That page blocks readers. Save it as a PDF instead."


async def fetch(url: str) -> tuple[str | None, str]:
    """Return `(page title, readable text)` for a public URL.

    Raises [Unreachable] for anything refused by the guards above, and for a
    page that answers with something there is no point indexing.
    """
    async with httpx.AsyncClient(timeout=TIMEOUT, follow_redirects=False) as client:
        for _ in range(MAX_REDIRECTS + 1):
            guard(url)
            async with client.stream("GET", url, headers=HEADERS) as response:
                if response.is_redirect:
                    location = response.headers.get("location")
                    if not location:
                        raise Unreachable("That link redirects nowhere.")
                    url = str(httpx.URL(url).join(location))
                    continue

                if response.status_code in BLOCKED_STATUSES:
                    raise Blocked(BLOCKED_MESSAGE)
                if response.status_code >= 400:
                    raise Unreachable(f"That page answered {response.status_code}.")

                content_type = (
                    response.headers.get("content-type", "").split(";")[0].strip().lower()
                )
                if not content_type.startswith(READABLE):
                    raise Unreachable(f"{content_type or 'That page'} is not a readable page.")

                body = bytearray()
                async for chunk in response.aiter_bytes():
                    body.extend(chunk)
                    if len(body) >= MAX_BYTES:
                        # Abandoned mid-stream on purpose. A truncated page
                        # still indexes; an endpoint that never stops would
                        # otherwise hold this function instance until the
                        # timeout, once per link.
                        break
                encoding = response.charset_encoding or "utf-8"

            # Decoded outside the stream but inside the loop: the value has
            # to be returned from the iteration that produced it, or the
            # redirect path leaves these names unbound.
            text = bytes(body).decode(encoding, errors="replace")
            if content_type.startswith("text/plain"):
                return None, _collapse(text)
            return readable(text)

    raise Unreachable("That link redirects too many times.")


def guard(url: str) -> None:
    """Refuse anything that is not a public http(s) address.

    Called again on every redirect hop, because a public host that forwards
    to `169.254.169.254` is the attack this is here to stop.
    """
    parsed = urlparse(url)
    if parsed.scheme.lower() not in ALLOWED_SCHEMES:
        raise Unreachable("Only http and https links can be read.")

    host = parsed.hostname
    if not host:
        raise Unreachable("That link has no address.")

    for address in _addresses(host):
        # `is_global` is the single check that covers private ranges,
        # loopback, link-local and the carrier-grade NAT block; `is_reserved`
        # catches the rest. Enumerating CIDRs by hand is how one gets missed.
        if not address.is_global or address.is_reserved:
            raise Unreachable("That link points inside a private network.")


def readable(document: str) -> tuple[str | None, str]:
    """Strip an HTML page to its title and its words.

    A regex rather than a parser, deliberately: the alternative is a new
    dependency in a function bundle, and what the index needs is the prose —
    not a DOM. Scripts and styles go first, because a page's JavaScript is
    the largest thing in it and none of it is what the page *says*.
    """
    body = _SCRIPT.sub(" ", document)

    found = _TITLE.search(document)
    title = _collapse(_TAG.sub(" ", found.group(1))) if found else None

    text = _TAG.sub(" ", body)
    return (title or None), _collapse(text)


def _collapse(text: str) -> str:
    """Entities decoded, runs of space squeezed, blank lines reduced to one."""
    text = html_module.unescape(text)
    text = _SPACE.sub(" ", text)
    text = _BLANK.sub("\n\n", text)
    return "\n".join(line.strip() for line in text.splitlines()).strip()


def _addresses(host: str) -> list[ipaddress.IPv4Address | ipaddress.IPv6Address]:
    """Every address this host resolves to. An IP literal resolves to itself.

    All of them, not the first: a name that answers with one public address
    and one private one must be refused, and taking `[0]` is how that gets
    through.
    """
    try:
        infos = socket.getaddrinfo(host, None, proto=socket.IPPROTO_TCP)
    except OSError as error:
        raise Unreachable("That link's address could not be found.") from error

    found = []
    for info in infos:
        try:
            found.append(ipaddress.ip_address(info[4][0]))
        except ValueError:
            continue
    if not found:
        raise Unreachable("That link's address could not be found.")
    return found
