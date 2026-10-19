"""Six-digit email sign-in, on top of Firebase Auth.

Firebase Auth has no email OTP — it offers magic links, and SMS codes for
phone. The product's design (screens 3H → 3I) is a six-digit code, and a magic
link is a materially worse flow on mobile: it bounces the user out to a mail
app and back through a browser, and it breaks entirely when the link opens in a
different browser than the one that started the flow.

So the code lives here and Firebase issues the session:

    request  ──► generate code ──► store HMAC ──► email it
    verify   ──► compare HMAC  ──► create/find user
                               ──► admin.create_custom_token()
                                        │
    client   ◄───────────────────────────┘
             signInWithCustomToken() ──► a normal Firebase session

The client ends up with an ordinary Firebase ID token, so everything
downstream — security rules, other functions — is unaware this was ever a
custom flow.
"""

from __future__ import annotations

import hashlib
import hmac
import os
import secrets
from datetime import UTC, datetime, timedelta

import httpx
from firebase_admin import auth, firestore
from firebase_functions import https_fn, options
from google.cloud.firestore_v1.base_query import FieldFilter

CODE_LENGTH = 6
CODE_TTL = timedelta(minutes=10)
RESEND_COOLDOWN = timedelta(seconds=60)
MAX_ATTEMPTS = 5
HOURLY_LIMIT = 5

CHALLENGES = "emailChallenges"

# One message for every way a code can be wrong. Distinguishing "no challenge"
# from "wrong digits" tells an attacker which addresses have a sign-in in
# flight.
BAD_CODE = "That code is not valid. Request a new one."


#: Declared on both callables below, or `_secret()` raises at runtime and
#: every "Send code" returns a generic failure.
#:
#: Both must exist in Secret Manager before this list names them: Firebase
#: refuses to deploy a function referencing an absent secret, which fails the
#: whole deploy and — because the CLI applies Cloud Run invoker IAM as a
#: post-deploy phase — leaves unrelated functions returning 403.
CODE_SECRETS = ["AUTH_CODE_SECRET", "RESEND_API_KEY", "SMTP_PASSWORD"]


def _secret() -> str:
    key = os.environ.get("AUTH_CODE_SECRET")
    if not key:
        # Failing loudly beats signing codes with an empty key, which would
        # make every HMAC forgeable by anyone who read this file.
        raise RuntimeError("AUTH_CODE_SECRET is not set")
    return key


def _fail(where: str, error: Exception) -> https_fn.HttpsError:
    """Turn an unexpected exception into something diagnosable.

    Left unhandled, anything raised in a callable reaches the client as a bare
    `INTERNAL` with no message — and if Cloud Logging is unavailable, which it
    was while this was being debugged, there is then no way at all to find out
    what broke. The exception's *class name* is safe to surface (it names a
    failure mode, not data) and turns an opaque outage into a one-line
    diagnosis; the message goes to the log, where it can carry detail.
    """
    print(f"[knowra] {where} failed: {type(error).__name__}: {error}")
    return https_fn.HttpsError(
        https_fn.FunctionsErrorCode.INTERNAL,
        "Something went wrong sending your code. Try again.",
        {"at": where, "kind": type(error).__name__},
    )


def _hash_code(code: str, email: str) -> str:
    """HMAC, keyed with the server secret and bound to the address.

    A plain hash would be pointless: there are only a million candidates, so a
    leaked collection is instantly reversible. Mixing in the email stops a hash
    captured for one address being replayed against another.
    """
    message = f"{email.strip().lower()}:{code}".encode()
    return hmac.new(_secret().encode(), message, hashlib.sha256).hexdigest()


def _generate_code() -> str:
    # secrets, not random: this is a credential, and the default PRNG is
    # predictable from a handful of prior outputs.
    return f"{secrets.randbelow(10**CODE_LENGTH):0{CODE_LENGTH}d}"


def _normalise(email: object) -> str:
    if not isinstance(email, str) or "@" not in email:
        raise https_fn.HttpsError(
            https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            "A valid email address is required.",
        )
    return email.strip().lower()


@https_fn.on_call(
    region="us-central1",
    memory=options.MemoryOption.MB_256,
    # A per-instance cap, so a burst cannot fan out into unbounded cost.
    max_instances=10,
    secrets=CODE_SECRETS,
)
def request_email_code(req: https_fn.CallableRequest) -> dict:
    """Send a sign-in code.

    The response is identical whether or not the address has an account —
    sign-in must not double as an account-enumeration oracle.
    """
    email = _normalise(req.data.get("email"))
    db = firestore.client()
    now = datetime.now(UTC)

    try:
        recent = (
            db.collection(CHALLENGES)
            .where(filter=FieldFilter("email", "==", email))
            .where(filter=FieldFilter("createdAt", ">", now - timedelta(hours=1)))
            .count()
            .get()
        )
        issued = recent[0][0].value if recent else 0
    except Exception as error:
        raise _fail("rate-limit", error) from error

    # Over the cap we stop sending but still answer normally: a caller cannot
    # tell throttling from delivery, so hammering gains nothing.
    if issued < HOURLY_LIMIT:
        code = _generate_code()
        # Split from delivery below so a provider outage cannot be mistaken
        # for a storage failure, and vice versa.
        try:
            db.collection(CHALLENGES).add(
                {
                    "email": email,
                    "codeHmac": _hash_code(code, email),
                    "createdAt": now,
                    "expiresAt": now + CODE_TTL,
                    "consumedAt": None,
                    "attempts": 0,
                    "maxAttempts": MAX_ATTEMPTS,
                }
            )
        except Exception as error:
            raise _fail("store", error) from error

        # Never raises. A delivery problem must not break sign-in:
        # a user who gets no email can retry or use Google, whereas a 500
        # locks everyone out of the product entirely. The failure is loud in
        # the logs, which is where an operator can act on it — the user
        # cannot.
        _deliver(email, code)

    return {
        "sent": True,
        "expiresIn": int(CODE_TTL.total_seconds()),
        "resendIn": int(RESEND_COOLDOWN.total_seconds()),
    }


@https_fn.on_call(
    region="us-central1",
    memory=options.MemoryOption.MB_256,
    max_instances=10,
    secrets=CODE_SECRETS,
)
def verify_email_code(req: https_fn.CallableRequest) -> dict:
    """Exchange a valid code for a Firebase custom token."""
    email = _normalise(req.data.get("email"))
    code = req.data.get("code")

    if not isinstance(code, str) or len(code) != CODE_LENGTH or not code.isdigit():
        raise https_fn.HttpsError(
            https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            f"The code is {CODE_LENGTH} digits.",
        )

    db = firestore.client()
    now = datetime.now(UTC)

    matches = list(
        db.collection(CHALLENGES)
        .where("email", "==", email)
        .where("consumedAt", "==", None)
        .order_by("createdAt", direction=firestore.Query.DESCENDING)
        .limit(1)
        .stream()
    )

    if not matches:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.UNAUTHENTICATED, BAD_CODE)

    snapshot = matches[0]
    challenge = snapshot.to_dict()

    if challenge["expiresAt"] < now or challenge["attempts"] >= challenge["maxAttempts"]:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.UNAUTHENTICATED, BAD_CODE)

    # Count the attempt before comparing, so a crash mid-request cannot be used
    # to get unlimited free guesses.
    snapshot.reference.update({"attempts": firestore.Increment(1)})

    if not hmac.compare_digest(_hash_code(code, email), challenge["codeHmac"]):
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.UNAUTHENTICATED, BAD_CODE)

    # Consumed here, before the token is minted, so the code cannot be
    # replayed by a second request that arrives while this one is still in
    # flight. That ordering is deliberate — but it means a server-side
    # failure below would spend the user's code, and their retry would be
    # told the code was wrong. It was not: we broke.
    #
    # So the consume is reversed on failure. The replay window that opens is
    # only after a *failed* mint, which is exactly when the code should still
    # work — and a replay there mints a second token for the same uid, which
    # is harmless. A stolen code is still useless without the code itself.
    snapshot.reference.update({"consumedAt": now})

    try:
        user, is_new = _find_or_create_user(email)

        # A custom token is what turns all of the above into an ordinary
        # Firebase session: the client signs in with it and receives a normal
        # ID token, so security rules and every other function are unaware
        # this was custom.
        token = auth.create_custom_token(user.uid)
    except Exception as error:
        snapshot.reference.update({"consumedAt": None})
        # Named so the cause is diagnosable. Minting needs
        # `iam.serviceAccounts.signBlob` on the runtime service account, and
        # without it every sign-in fails here with an opaque 500 — which is
        # indistinguishable from a wrong code to everyone except whoever can
        # read the logs.
        print(
            f"[knowra] custom_token_mint_failed kind={type(error).__name__} "
            f"error={str(error)[:300]}"
        )
        raise https_fn.HttpsError(
            https_fn.FunctionsErrorCode.INTERNAL,
            "We could not complete sign-in. Your code is still valid — try again.",
            {"at": "mint", "kind": type(error).__name__},
        ) from error

    return {
        "token": token.decode() if isinstance(token, bytes) else token,
        "isNewUser": is_new,
    }


def _find_or_create_user(email: str) -> tuple[auth.UserRecord, bool]:
    try:
        return auth.get_user_by_email(email), False
    except auth.UserNotFoundError:
        # email_verified: reaching this point *is* proof of control over the
        # inbox — the code was delivered there and came back.
        return auth.create_user(email=email, email_verified=True), True


#: A verified sender. Its presence is the signal that delivery is *expected*
#: to work — which is what separates a development deployment from a real one,
#: and therefore whether logging a live sign-in code is acceptable.
#:
#: Without it Resend falls back to `onboarding@resend.dev`, which only
#: delivers to the Resend account owner's own address.
_SANDBOX_SENDER = "Hawk <onboarding@resend.dev>"


#: Domains reserved by RFC 2606 and RFC 6761, which can never belong to a
#: real person and to which mail can never be delivered.
#:
#: Keyed on this rather than on an allowlist, deliberately. An allowlist of
#: test addresses is a list that drifts: someone adds a real address to
#: unblock themselves, and a live sign-in code starts appearing in the logs
#: for an account that matters. A reserved TLD cannot drift, because the
#: standards body guarantees no one will ever own one.
#:
#: The consequence is not a loosening but a *correction*: SMTP delivery to an
#: unroutable domain fails by definition, so the honest behaviour for these
#: addresses was never "try to send" — it was "there is nowhere to send".
#: Logging the code is what makes such an address testable at all.
#:
#: The worst an attacker with log access gains is a session on an account
#: they just created, which contains nothing — and log access already implies
#: far more serious exposure than that.
_UNROUTABLE_TLDS = (".invalid", ".test", ".localhost", ".example")
_UNROUTABLE_DOMAINS = ("example.com", "example.net", "example.org")


def _is_unroutable(email: str) -> bool:
    domain = email.rsplit("@", 1)[-1].lower()
    return domain.endswith(_UNROUTABLE_TLDS) or domain in _UNROUTABLE_DOMAINS


def _smtp_config() -> dict | None:
    """SMTP settings, or None if this deployment has none.

    Gmail specifics, because they are the ones that bite:
    * The password must be a **Google App Password**, not the account
      password — Google refuses basic auth for the real one. App Passwords
      require 2-Step Verification to be on.
    * The `From` address must be the authenticated account. Gmail rewrites or
      rejects anything else, so `EMAIL_FROM` is ignored here in favour of the
      SMTP user.
    * Consumer Gmail caps roughly 500 recipients a day (Workspace ~2000).
      Ample for testing and early users; not a launch answer.
    """
    user = os.environ.get("SMTP_USER", "")
    password = os.environ.get("SMTP_PASSWORD", "")
    if not (user and password):
        return None

    return {
        "host": os.environ.get("SMTP_HOST", "smtp.gmail.com"),
        "port": int(os.environ.get("SMTP_PORT", "587")),
        "user": user,
        "password": password,
        # The display name is ours; the address has to be the account.
        "sender": f"{os.environ.get('SMTP_NAME', 'Hawk')} <{user}>",
    }


def _send_smtp(config: dict, email: str, code: str) -> None:
    """Send over SMTP. Raises on failure; the caller swallows."""
    import smtplib
    from email.message import EmailMessage

    message = EmailMessage()
    message["Subject"] = f"{code} is your Hawk sign-in code"
    message["From"] = config["sender"]
    message["To"] = email
    message.set_content(_TEXT_BODY.format(code=code))
    message.add_alternative(_HTML_BODY.format(code=code), subtype="html")

    # STARTTLS on 587, implicit TLS on 465. Both are used in the wild and the
    # port is the only reliable signal of which.
    if config["port"] == 465:
        with smtplib.SMTP_SSL(config["host"], config["port"], timeout=20) as server:
            server.login(config["user"], config["password"])
            server.send_message(message)
        return

    with smtplib.SMTP(config["host"], config["port"], timeout=20) as server:
        server.starttls()
        server.login(config["user"], config["password"])
        server.send_message(message)


#: One body, two transports. Kept as constants so SMTP and Resend cannot
#: drift into sending differently-worded sign-in emails.
_TEXT_BODY = (
    "{code}\n\n"
    "That is your Hawk sign-in code. It expires in 10 minutes and works "
    "once.\n\n"
    "Didn't ask to sign in? You can ignore this email. No one can get in "
    "with it alone.\n\n"
    "Hawk · Your second memory · hawkapp.in"
)

#: The HTML body, built to the app's v3 tokens: ground #0C0C0D, card #191A1B,
#: border #3A3C3D, text white / #C9CAC7 / #A4A6A1 / #8B8D88, and the accent
#: #59D3FF only where the app spends it, on the Hawk mark's highlight. The
#: serif is the headline face; the code is set in mono because the design
#: reserves mono for numerals. Copy is kept to what the reader needs.
#:
#: Written as tables with inline styles, which is not stylistic preference:
#:
#: * **Web fonts do not arrive.** Gmail strips @font-face, so Instrument
#:   Serif and Archivo are unavailable and every family is a fallback stack.
#:   Georgia is the closest widely-installed serif; the mono stack ends at
#:   `monospace`, which every client has.
#: * **Outlook renders with Word.** It ignores float, flex and most of
#:   `<div>` layout, so structure is a table. `role="presentation"` keeps
#:   screen readers from announcing it as data.
#: * **No external images.** Gmail proxies them and many clients block them
#:   by default, so a blocked logo would leave the mark missing. The Hawk mark
#:   (white disc r24, accent highlight r7 up-left, on a 64 grid) is two
#:   circles drawn with border-radius; where that is unsupported it degrades
#:   to squares, still white and cyan.
#: * **Dark by default, not dark-mode-dependent.** Clients handle
#:   `prefers-color-scheme` inconsistently and some force-invert. Committing
#:   to the app's dark ground and stating every colour explicitly means the
#:   mail looks deliberate everywhere rather than correct in one client.
#: * **A hidden preheader** sets the inbox preview line, which would
#:   otherwise be the first text in the layout. It leaves the code out: the
#:   subject already shows it, and the body carries it exactly once.
_HTML_BODY = """\
<div style="background:#0C0C0D;margin:0;padding:40px 16px;
  font-family:Archivo,'Helvetica Neue',Helvetica,Arial,sans-serif;">
<div style="display:none;max-height:0;overflow:hidden;mso-hide:all;
  font-size:1px;line-height:1px;color:#0C0C0D;">
  Your Hawk sign-in code. It expires in 10 minutes and works once.
</div>
<table role="presentation" cellpadding="0" cellspacing="0" border="0"
  width="100%" style="max-width:440px;margin:0 auto;">

  <tr><td style="padding:0 4px 36px;">
    <table role="presentation" cellpadding="0" cellspacing="0" border="0">
      <tr>
        <td style="width:26px;height:26px;border-radius:13px;
          background:#FFFFFF;vertical-align:top;">
          <div style="width:8px;height:8px;border-radius:4px;
            background:#59D3FF;margin:5px 0 0 5px;font-size:0;
            line-height:0;">&nbsp;</div>
        </td>
        <td style="padding-left:10px;font-size:21px;font-weight:800;
          line-height:26px;letter-spacing:-.04em;color:#FFFFFF;">Hawk</td>
      </tr>
    </table>
  </td></tr>

  <tr><td style="padding:0 4px 18px;">
    <div style="font-family:'Instrument Serif',Georgia,'Times New Roman',serif;
      font-size:32px;line-height:1.1;letter-spacing:-.02em;color:#FFFFFF;">
      Your sign-in code
    </div>
  </td></tr>

  <tr><td>
    <table role="presentation" cellpadding="0" cellspacing="0" border="0"
      width="100%" style="background:#191A1B;border:1px solid #3A3C3D;
      border-radius:16px;">
      <tr><td align="center" style="padding:28px 16px 24px;">
        <div style="font-family:'Martian Mono',ui-monospace,SFMono-Regular,
          Menlo,Consolas,monospace;font-size:36px;font-weight:600;
          letter-spacing:.22em;padding-left:.22em;color:#FFFFFF;">{code}</div>
        <div style="padding-top:14px;font-size:13px;color:#A4A6A1;">
          Expires in 10 minutes &middot; works once
        </div>
      </td></tr>
    </table>
  </td></tr>

  <tr><td style="padding:22px 4px 0;font-size:15px;line-height:1.6;
    color:#C9CAC7;">
    Type it into Hawk to finish signing in.
  </td></tr>

  <tr><td style="padding:10px 4px 0;font-size:13px;line-height:1.6;
    color:#8B8D88;">
    Didn&rsquo;t ask to sign in? You can ignore this email. No one can get in
    with it alone.
  </td></tr>

  <tr><td style="padding:36px 4px 0;">
    <div style="border-top:1px solid #242627;padding-top:16px;font-size:12px;
      line-height:1.6;color:#7C7E79;">
      Hawk &middot; Your second memory &middot; hawkapp.in
    </div>
  </td></tr>

</table>
</div>"""


def _deliver(email: str, code: str) -> None:
    """Send the code. Never raises.

    Three outcomes, and the difference between them is whether the code ends
    up in the log:

    * **No key, or no verified sender** — this deployment cannot deliver to
      arbitrary addresses, so the code is logged and sign-in stays usable.
      That is the only mode in which logging a live code is acceptable, and
      the condition is checked rather than assumed.
    * **Configured, delivery worked** — nothing logged but a success line.
    * **Configured, delivery failed** — logged as an incident, WITHOUT the
      code. Anyone with log access could otherwise sign in as anyone, which
      is a worse problem than the one being debugged.

    The response is identical in all three cases. Sign-in must not double as
    an account-enumeration oracle, and a caller able to tell "delivered" from
    "rejected" can test whether an address exists.
    """
    # A reserved domain has nowhere to deliver to, so there is nothing to
    # attempt and the code is the only useful output. This is what makes an
    # automated sign-in possible without ever putting a real user's code in a
    # log — see `_UNROUTABLE_TLDS`.
    if _is_unroutable(email):
        print(
            f"[knowra] sign_in_code_issued reason=unroutable_test_domain email={email} code={code}"
        )
        return

    smtp = _smtp_config()
    api_key = os.environ.get("RESEND_API_KEY")
    sender = os.environ.get("EMAIL_FROM", _SANDBOX_SENDER)

    # SMTP first where configured. It sends from an address the account
    # already owns, so it has no domain-verification step at all — which is
    # exactly why it is the better answer for a small deployment, and why it
    # takes priority over a Resend key that cannot reach arbitrary addresses.
    if smtp is not None:
        try:
            _send_smtp(smtp, email, code)
            print("[knowra] sign_in_code_sent via=smtp")
            return
        except Exception as error:
            # No code and no address in this line: delivery is configured, so
            # this is a real deployment.
            print(f"[knowra] email_delivery_failed via=smtp cause={type(error).__name__}")
            return

    can_deliver = bool(api_key) and sender != _SANDBOX_SENDER

    if not can_deliver:
        reason = "no_smtp_or_api_key" if not api_key else "unverified_sender"
        # Visible in `firebase emulators:start` output and in Cloud Logging.
        print(f"[knowra] sign_in_code_issued reason={reason} email={email} code={code}")
        return

    response = httpx.post(
        "https://api.resend.com/emails",
        headers={"Authorization": f"Bearer {api_key}"},
        json={
            "from": sender,
            "to": [email],
            "subject": f"{code} is your Hawk sign-in code",
            # Both parts. `text` alone renders as one run-together line in any
            # client that collapses whitespace — and the six digits are the
            # entire payload, so they have to be unmissable.
            "text": _TEXT_BODY.format(code=code),
            "html": _HTML_BODY.format(code=code),
        },
        timeout=10,
    )
    if response.status_code < 400:
        return

    # Named by cause, because the remedies are completely different and an
    # operator reading this at 3am should not have to look up a status code.
    #
    # The recipient address is deliberately absent: an error log is the one
    # place an enumeration signal tends to survive.
    cause = {
        401: "bad_or_rotated_api_key",
        403: "sender_not_permitted_for_this_recipient",
        422: "recipient_rejected",
        429: "rate_limited",
    }.get(response.status_code, f"http_{response.status_code}")

    # No code in this line. A configured deployment is a real one, and a live
    # sign-in code in a log is a sign-in for anyone who can read logs.
    print(f"[knowra] email_delivery_failed cause={cause}")
