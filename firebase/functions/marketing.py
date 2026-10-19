"""Offers and news by email, sent from the Firebase console.

Three pieces, and the user's choice runs through all of them:

* **`set_marketing_consent`** — the app's "Offers and news by email" switch.
  **On by default** (user decision, 2026-09-29): a user with no recorded
  choice gets campaigns, and only an explicit "off" — the switch, or the
  unsubscribe link — stops them. The server records when either happened.
* **`on_campaign_written`** — the sender. A campaign is a document in the
  `campaigns` collection, written in the Firebase console:

      subject   "Hawk Premium is 50% off this week"
      body      an array of paragraphs (easiest in the console), or one
                string with a typed \\n where a line breaks
      audience  "test"   only the addresses in `testTo`
                "users"  every user who has not turned offers off
      testTo    ["karnav.p.018@gmail.com"]    (for audience "test")
      status    "draft", then "send" to send it

  Setting status to "send" sends it. The function writes back "sending",
  then "sent", "paused" (the daily limit was reached; set "send" again the
  next day and it carries on where it stopped) or "error" with a note.
* **`unsubscribe`** — the link at the foot of every email, and the one-click
  `List-Unsubscribe` header mail apps show. It turns the switch off.

Sent through the same Gmail account as sign-in codes. Consumer Gmail allows
about 500 recipients a day across both, so campaigns stop at
`MARKETING_DAILY_CAP` and leave room for sign-in codes. A campaign never
sends to the same person twice: each recipient is recorded as it is sent, so
to send a test again, make a new campaign document.
"""

from __future__ import annotations

import hashlib
import hmac
import html
import os
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime

from firebase_admin import firestore
from firebase_functions import firestore_fn, https_fn, options

import email_codes

CAMPAIGNS = "campaigns"
OPT_OUTS = "marketingOptOuts"
STATS = "mailStats"

AUDIENCE_TEST = "test"
#: Every user who has not turned offers off, deactivated accounts aside.
AUDIENCE_USERS = "users"
#: Other names people type for it in the console.
_AUDIENCE_ALIASES = {"opted_in": AUDIENCE_USERS, "all": AUDIENCE_USERS, "everyone": AUDIENCE_USERS}


def subscribed(profile: dict) -> bool:
    """Whether a user gets campaigns: yes unless they turned offers off.

    A profile with no `marketingOptIn` at all is subscribed — that is the
    default. Deactivated accounts are left alone: someone who paused Hawk
    did not ask to hear about offers in the meantime.
    """
    return profile.get("marketingOptIn") is not False and profile.get("status") != "deactivated"


#: Most addresses one test send may list: a test is for checking, not a
#: side door around consent.
TEST_LIMIT = 25

UNSUBSCRIBE_URL = "https://us-central1-knowra-506719.cloudfunctions.net/unsubscribe"

#: The secret that signs unsubscribe links. Shared with sign-in codes, with
#: its own prefix so a token for one can never be used as the other.
SECRETS = ["AUTH_CODE_SECRET", "SMTP_PASSWORD"]


def daily_cap() -> int:
    """Marketing emails allowed per UTC day, below Gmail's limit."""
    try:
        return max(0, int(os.environ.get("MARKETING_DAILY_CAP", "300")))
    except ValueError:
        return 300


# ---------------------------------------------------------------- template

#: The paragraph a new campaign starts with. Sending is refused while it is
#: still there, so a half-written campaign cannot go out.
WRITE_HERE = "Write your message here."


def template_fields(existing: dict) -> dict:
    """The fields a new campaign document is missing, pre-filled.

    The Firebase console has no templates, so a campaign created there with a
    single field gets the rest written in by [on_campaign_written]. Only
    missing fields are added; anything typed is kept. The test address and
    the sign-off come from `.env` (CAMPAIGN_TEST_TO, CAMPAIGN_SIGNATURE).
    """
    test_to = [e.strip() for e in os.environ.get("CAMPAIGN_TEST_TO", "").split(",") if e.strip()]
    signature = os.environ.get("CAMPAIGN_SIGNATURE", "").strip() or "The Hawk team"
    defaults = {
        "subject": "",
        "body": ["Hi,", WRITE_HERE, "Thank you,", signature],
        "audience": AUDIENCE_TEST,
        "testTo": test_to,
        "status": "draft",
        "createdAt": firestore.SERVER_TIMESTAMP,
    }
    return {key: value for key, value in defaults.items() if key not in existing}


# ------------------------------------------------------------ unsubscribe


def unsubscribe_token(kind: str, ident: str, *, secret: str | None = None) -> str:
    """A signature proving an unsubscribe link came from Hawk.

    [kind] is "u" for a user id or "e" for an address that is not a user
    (a test recipient). Without the signature, anyone could turn off anyone's
    emails by guessing ids.
    """
    key = (secret if secret is not None else os.environ.get("AUTH_CODE_SECRET", "")).encode()
    message = f"unsubscribe:{kind}:{ident.strip().lower()}".encode()
    return hmac.new(key, message, hashlib.sha256).hexdigest()[:32]


def valid_token(kind: str, ident: str, token: str, *, secret: str | None = None) -> bool:
    if kind not in ("u", "e") or not ident or not token:
        return False
    return hmac.compare_digest(unsubscribe_token(kind, ident, secret=secret), token)


def unsubscribe_link(kind: str, ident: str, *, secret: str | None = None) -> str:
    from urllib.parse import urlencode

    query = urlencode({"k": kind, "i": ident, "t": unsubscribe_token(kind, ident, secret=secret)})
    return f"{UNSUBSCRIBE_URL}?{query}"


# ------------------------------------------------------------------ render


#: Why this person is getting the email, said at its foot. It has to be true
#: for the audience, and say how to stop it: offers are on by default, so a
#: user never chose them and must be told where the switch is.
REASONS = {
    AUDIENCE_USERS: (
        "You get these emails because you use Hawk. Turn them off in the app "
        "under Privacy and data, or unsubscribe here."
    ),
    AUDIENCE_TEST: "You're getting this email as one of Hawk's testers.",
}


def body_text(raw: object) -> str:
    """A campaign's body as one string, paragraphs separated by blank lines.

    The Firebase console's text box has no line breaks, so a body may also be
    an array of paragraphs, or a string with a typed `\\n` for each break.
    """
    if isinstance(raw, list):
        return "\n\n".join(str(p).strip() for p in raw if str(p).strip())
    return str(raw or "").replace("\\n", "\n").strip()


def paragraphs(body: str) -> list[str]:
    """The body split on blank lines, each paragraph on one line."""
    blocks = [" ".join(part.split()) for part in body.replace("\r\n", "\n").split("\n\n")]
    return [b for b in blocks if b]


def render(
    subject: str, body: str, link: str, *, reason: str = REASONS[AUDIENCE_USERS]
) -> tuple[str, str]:
    """The plain-text and HTML versions of one email."""
    parts = paragraphs(body)
    footer = f"{reason}\nUnsubscribe: {link}\n\nHawk · hawkapp.in"
    text = "\n\n".join(parts) + "\n\n" + footer
    rendered = "".join(
        f'<p style="margin:0 0 16px;font:16px/1.55 Helvetica,Arial,sans-serif;color:#1d1f21">'
        f"{html.escape(p)}</p>"
        for p in parts
    )
    page = (
        '<!doctype html><html><body style="margin:0;background:#f3f5f0;padding:24px">'
        '<div style="max-width:560px;margin:0 auto;background:#ffffff;border-radius:16px;'
        'padding:28px 28px 20px">'
        '<p style="margin:0 0 20px;font:800 20px Helvetica,Arial,sans-serif;color:#0c0c0d">'
        "Hawk</p>"
        f"{rendered}"
        '<p style="margin:24px 0 0;font:13px/1.5 Helvetica,Arial,sans-serif;color:#6b6f67">'
        f"{html.escape(reason)} "
        f'<a href="{html.escape(link)}" style="color:#6b6f67">Unsubscribe</a>.'
        "<br>Hawk · hawkapp.in</p>"
        "</div></body></html>"
    )
    return text, page


# -------------------------------------------------------------- recipients


@dataclass(frozen=True)
class Recipient:
    #: What the "already sent" record is keyed by: the uid, or the address.
    key: str
    email: str
    uid: str | None = None

    @property
    def link_kind(self) -> tuple[str, str]:
        return ("u", self.uid) if self.uid else ("e", self.email)


def _clean_email(value: object) -> str:
    text = str(value or "").strip().lower()
    return text if "@" in text and " " not in text else ""


def plan_recipients(
    audience: str,
    test_to: list | None,
    users: list[tuple[str, dict]],
    opted_out: set[str],
) -> list[Recipient]:
    """Who a campaign goes to, before anything is sent.

    [users] are (uid, profile) pairs, filtered here by [subscribed];
    [opted_out] holds addresses that unsubscribed without an account.
    """
    seen: set[str] = set()
    out: list[Recipient] = []

    if audience == AUDIENCE_TEST:
        for raw in (test_to or [])[:TEST_LIMIT]:
            email = _clean_email(raw)
            if email and email not in seen and email not in opted_out:
                seen.add(email)
                out.append(Recipient(key=email, email=email))
        return out

    if audience == AUDIENCE_USERS:
        for uid, profile in users:
            if not subscribed(profile):
                continue
            email = _clean_email(profile.get("email"))
            if email and email not in seen and email not in opted_out:
                seen.add(email)
                out.append(Recipient(key=uid, email=email, uid=uid))
    return out


# ------------------------------------------------------------------ sending


@dataclass
class Outcome:
    sent: list[str]
    failed: int = 0
    skipped: int = 0
    stopped_at_cap: bool = False


def run(
    recipients: list[Recipient],
    already_sent: set[str],
    room: int,
    deliver: Callable[[Recipient], None],
) -> Outcome:
    """Send to everyone not yet sent to, up to [room] emails.

    [deliver] raises when one address fails; that one is counted and the
    rest still go.
    """
    outcome = Outcome(sent=[])
    for recipient in recipients:
        if recipient.key in already_sent:
            outcome.skipped += 1
            continue
        if len(outcome.sent) + outcome.failed >= room:
            outcome.stopped_at_cap = True
            break
        try:
            deliver(recipient)
            outcome.sent.append(recipient.key)
        except Exception as error:
            outcome.failed += 1
            print(f"[knowra] marketing_send_failed cause={type(error).__name__}")
    return outcome


def _smtp_sender(subject: str, body: str, reason: str):
    """A deliver function over one SMTP connection, and its closer."""
    import smtplib
    from email.message import EmailMessage

    config = email_codes._smtp_config()
    if config is None:
        raise RuntimeError("SMTP is not configured.")

    if config["port"] == 465:
        server = smtplib.SMTP_SSL(config["host"], config["port"], timeout=20)
    else:
        server = smtplib.SMTP(config["host"], config["port"], timeout=20)
        server.starttls()
    server.login(config["user"], config["password"])

    def deliver(recipient: Recipient) -> None:
        kind, ident = recipient.link_kind
        link = unsubscribe_link(kind, ident)
        text, page = render(subject, body, link, reason=reason)
        message = EmailMessage()
        message["Subject"] = subject
        message["From"] = config["sender"]
        message["To"] = recipient.email
        message["List-Unsubscribe"] = f"<{link}>"
        message["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
        message.set_content(text)
        message.add_alternative(page, subtype="html")
        server.send_message(message)

    def close() -> None:
        # Everything has been sent by now; a connection that will not close
        # cleanly is worth a log line, not a failed campaign.
        try:
            server.quit()
        except Exception as error:
            print(f"[knowra] marketing_smtp_close_failed cause={type(error).__name__}")

    return deliver, close


def _today(now: datetime) -> str:
    return now.astimezone(UTC).strftime("%Y-%m-%d")


def send_campaign(db, campaign_id: str, data: dict, now: datetime) -> dict:
    """Send one campaign. Returns the fields written back to it."""
    subject = str(data.get("subject") or "").strip()
    body = body_text(data.get("body"))
    audience = str(data.get("audience") or "").strip().lower()
    audience = _AUDIENCE_ALIASES.get(audience, audience)

    if not subject or not body:
        return {"status": "error", "note": "Add a subject and a body, then set status to send."}
    if WRITE_HERE in paragraphs(body):
        return {
            "status": "error",
            "note": f'Replace "{WRITE_HERE}" in the body with your message, '
            "then set status to send.",
        }
    if audience not in (AUDIENCE_TEST, AUDIENCE_USERS):
        return {"status": "error", "note": 'Set audience to "test" or "users".'}

    opted_out = {doc.id for doc in db.collection(OPT_OUTS).stream()}
    users: list[tuple[str, dict]] = []
    if audience == AUDIENCE_USERS:
        # Every profile, not a query on the flag: offers are on by default,
        # so most subscribed users have no `marketingOptIn` field at all, and
        # a query for `== True` would miss every one of them.
        users = [(doc.id, doc.to_dict() or {}) for doc in db.collection("users").stream()]
    recipients = plan_recipients(audience, data.get("testTo"), users, opted_out)
    if not recipients:
        return {"status": "sent", "note": "Nobody to send to.", "sentCount": 0}

    campaign = db.collection(CAMPAIGNS).document(campaign_id)
    already = {doc.id for doc in campaign.collection("recipients").stream()}

    stats_ref = db.collection(STATS).document(_today(now))
    stats = stats_ref.get()
    used = int((stats.to_dict() or {}).get("marketing", 0)) if stats.exists else 0
    room = max(0, daily_cap() - used)

    if room == 0 and any(r.key not in already for r in recipients):
        return {
            "status": "paused",
            "sentCount": len(already),
            "note": "Today's sending limit is used up. Set status to send again tomorrow.",
        }

    deliver, close = _smtp_sender(subject, body, REASONS[audience])
    try:
        outcome = run(recipients, already, room, deliver)
    finally:
        close()

    batch = db.batch()
    for key in outcome.sent:
        batch.set(campaign.collection("recipients").document(key), {"sentAt": now})
    batch.set(stats_ref, {"marketing": firestore.Increment(len(outcome.sent))}, merge=True)
    batch.commit()

    total_sent = len(already) + len(outcome.sent)
    result = {
        "sentCount": total_sent,
        "failedCount": outcome.failed,
        "lastRunAt": now,
    }
    if outcome.stopped_at_cap:
        result |= {
            "status": "paused",
            "note": "Stopped at today's sending limit. Set status to send again "
            "tomorrow to carry on.",
        }
    else:
        result |= {"status": "sent", "note": None}
    print(
        f"[knowra] campaign_sent id={campaign_id} audience={audience} "
        f"sent={len(outcome.sent)} failed={outcome.failed} paused={outcome.stopped_at_cap}"
    )
    return result


@firestore_fn.on_document_written(
    document=CAMPAIGNS + "/{campaignId}",
    region="us-central1",
    memory=options.MemoryOption.MB_512,
    timeout_sec=540,
    secrets=SECRETS,
)
def on_campaign_written(event: firestore_fn.Event) -> None:
    """Fills in a new campaign's fields; sends one when its status becomes "send"."""
    change = event.data
    after = change.after.to_dict() if change.after and change.after.exists else None
    before = change.before.to_dict() if change.before and change.before.exists else None

    # Just created in the console and not being sent: write in whatever the
    # template has that it lacks. The write fires this trigger again, as an
    # update, which then does nothing.
    if after is not None and before is None and after.get("status") != "send":
        missing = template_fields(after)
        if missing:
            db = firestore.client()
            db.collection(CAMPAIGNS).document(event.params["campaignId"]).set(missing, merge=True)
        return

    if not after or after.get("status") != "send":
        return
    if before and before.get("status") == "send":
        return

    db = firestore.client()
    campaign_id = event.params["campaignId"]
    ref = db.collection(CAMPAIGNS).document(campaign_id)

    # Claimed in a transaction. Firestore may deliver this trigger more than
    # once, and two runs that both saw "send" would both start sending.
    @firestore.transactional
    def _claim(transaction) -> dict | None:  # type: ignore[no-untyped-def]
        snapshot = ref.get(transaction=transaction)
        data = snapshot.to_dict() or {}
        if data.get("status") != "send":
            return None
        transaction.update(ref, {"status": "sending", "note": None})
        return data

    claimed = _claim(db.transaction())
    if claimed is None:
        return
    try:
        result = send_campaign(db, campaign_id, claimed, datetime.now(UTC))
    except Exception as error:
        print(f"[knowra] campaign_failed id={campaign_id} cause={type(error).__name__}")
        result = {"status": "error", "note": f"Sending failed: {type(error).__name__}."}
    ref.set(result, merge=True)


# ----------------------------------------------------------------- consent


@https_fn.on_call(region="us-central1", memory=options.MemoryOption.MB_256)
def set_marketing_consent(req: https_fn.CallableRequest) -> dict:
    """The app's "Offers and news by email" switch."""
    if req.auth is None:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.UNAUTHENTICATED, "Sign in first.")
    opt_in = (req.data or {}).get("optIn")
    if not isinstance(opt_in, bool):
        raise https_fn.HttpsError(
            https_fn.FunctionsErrorCode.INVALID_ARGUMENT, "optIn must be true or false."
        )

    db = firestore.client()
    stamp = firestore.SERVER_TIMESTAMP
    update = {"marketingOptIn": opt_in, "updatedAt": stamp}
    update["marketingConsentAt" if opt_in else "marketingOptOutAt"] = stamp
    if opt_in:
        update["marketingConsentSource"] = "app"
    db.collection("users").document(req.auth.uid).set(update, merge=True)
    return {"optIn": opt_in}


_PAGE = (
    '<!doctype html><html><head><meta name="viewport" content="width=device-width,'
    'initial-scale=1"><title>Hawk</title></head>'
    '<body style="margin:0;background:#f3f5f0;font:16px/1.5 Helvetica,Arial,sans-serif;'
    'color:#1d1f21"><div style="max-width:480px;margin:48px auto;background:#fff;'
    'border-radius:16px;padding:28px">'
    '<p style="margin:0 0 16px;font:800 20px Helvetica,Arial,sans-serif">Hawk</p>{content}'
    "</div></body></html>"
)


def _page(content: str, status: int = 200) -> https_fn.Response:
    return https_fn.Response(
        _PAGE.format(content=content),
        status=status,
        headers={"Content-Type": "text/html; charset=utf-8"},
    )


@https_fn.on_request(region="us-central1", memory=options.MemoryOption.MB_256, secrets=SECRETS)
def unsubscribe(req: https_fn.Request) -> https_fn.Response:
    """Turns offers and news off, from the link in an email.

    A GET only shows a button: mail scanners open links on their own, and an
    unsubscribe that fired on a GET would switch people off who never
    clicked. The button, and a mail app's one-click unsubscribe, POST.
    """
    kind = req.args.get("k", "")
    ident = req.args.get("i", "")
    token = req.args.get("t", "")
    if not valid_token(kind, ident, token):
        return _page("<p>This unsubscribe link is not valid.</p>", status=400)

    if req.method != "POST":
        from urllib.parse import urlencode

        action = f"?{urlencode({'k': kind, 'i': ident, 't': token})}"
        return _page(
            "<p>Stop getting offers and news from Hawk by email?</p>"
            f'<form method="post" action="{html.escape(action)}">'
            '<button type="submit" style="font:600 16px Helvetica,Arial,sans-serif;'
            "background:#0c0c0d;color:#fff;border:0;border-radius:999px;"
            'padding:12px 22px;cursor:pointer">Unsubscribe</button></form>'
        )

    db = firestore.client()
    stamp = firestore.SERVER_TIMESTAMP
    if kind == "u":
        db.collection("users").document(ident).set(
            {"marketingOptIn": False, "marketingOptOutAt": stamp}, merge=True
        )
    else:
        db.collection(OPT_OUTS).document(ident.strip().lower()).set({"at": stamp})
    print(f"[knowra] marketing_unsubscribed kind={kind}")
    return _page(
        "<p>You're unsubscribed. Hawk won't send you offers or news by email.</p>"
        '<p style="color:#6b6f67">Sign-in codes still arrive when you ask for them.</p>'
    )
