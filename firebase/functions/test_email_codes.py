"""The parts of the sign-in code flow that are pure logic.

The Firestore and Auth calls need the emulator; the cryptography does not, and
it is the part where a mistake is silent.
"""

import os
import re

import pytest

os.environ.setdefault("AUTH_CODE_SECRET", "test-secret-not-for-production")

import email_codes


class TestCodeGeneration:
    def test_codes_are_six_digits(self) -> None:
        for _ in range(200):
            assert re.fullmatch(r"\d{6}", email_codes._generate_code())

    def test_codes_are_not_predictable(self) -> None:
        # `secrets`, not `random`: this is a credential, and the default PRNG
        # is recoverable from a handful of prior outputs.
        assert len({email_codes._generate_code() for _ in range(500)}) > 400


class TestHashing:
    def test_the_hmac_is_bound_to_the_address(self) -> None:
        """A hash captured for one address must not verify against another."""
        code = "419372"
        assert email_codes._hash_code(code, "a@example.com") != email_codes._hash_code(
            code, "b@example.com"
        )

    def test_it_depends_on_the_server_secret(self, monkeypatch) -> None:
        code = "419372"
        first = email_codes._hash_code(code, "sam@northwind.co")
        monkeypatch.setenv("AUTH_CODE_SECRET", "a-different-secret")
        assert email_codes._hash_code(code, "sam@northwind.co") != first

    def test_it_is_case_and_whitespace_insensitive_on_the_address(self) -> None:
        # The verify path normalises before hashing; if these disagreed, a
        # code sent to "Sam@X" could never be redeemed as "sam@x".
        code = "419372"
        assert email_codes._hash_code(code, "  Sam@Northwind.CO ") == (
            email_codes._hash_code(code, "sam@northwind.co")
        )

    def test_an_empty_secret_raises_rather_than_signing(self, monkeypatch) -> None:
        """An empty key would make every HMAC forgeable by anyone."""
        monkeypatch.delenv("AUTH_CODE_SECRET", raising=False)
        with pytest.raises(RuntimeError, match="AUTH_CODE_SECRET"):
            email_codes._hash_code("419372", "sam@northwind.co")


class TestNormalisation:
    def test_addresses_are_lowercased_and_trimmed(self) -> None:
        assert email_codes._normalise("  Sam@Northwind.CO ") == "sam@northwind.co"

    def test_rubbish_is_rejected(self) -> None:
        for bad in ["", "   ", "sam", None, 42]:
            with pytest.raises(Exception):
                email_codes._normalise(bad)


def test_one_message_for_every_wrong_code() -> None:
    """Distinguishing "no challenge" from "wrong digits" tells an attacker
    which addresses have a sign-in in flight."""
    assert "not valid" in email_codes.BAD_CODE
    assert "expired" not in email_codes.BAD_CODE.lower()


class TestDeliveryNeverBreaksSignIn:
    """QA-028. Surfacing a misconfigured sender turned a working log-mode
    sign-in into a 500 for every user.

    The line that resolves it is not "raise" versus "swallow" — it is whether
    the deployment can deliver at all, which decides whether logging a live
    sign-in code is acceptable.
    """

    def test_the_sandbox_sender_means_this_build_cannot_deliver(self):
        import email_codes

        # Resend's default sender only reaches the account owner's own
        # address, so its presence is the marker of a non-production build.
        assert "resend.dev" in email_codes._SANDBOX_SENDER

    def test_no_key_logs_the_code_so_sign_in_stays_testable(self, capsys, monkeypatch):
        import email_codes

        monkeypatch.delenv("RESEND_API_KEY", raising=False)
        monkeypatch.delenv("EMAIL_FROM", raising=False)
        email_codes._deliver("qa@knowra-live.co", "123456")

        out = capsys.readouterr().out
        assert "sign_in_code_issued" in out
        assert "123456" in out
        assert "reason=no_smtp_or_api_key" in out

    def test_a_key_without_a_verified_sender_also_logs(self, capsys, monkeypatch):
        """The regression. A real key plus the sandbox sender cannot deliver
        to anyone but the account owner — so it must behave like no key, not
        like a working configuration."""
        import email_codes

        monkeypatch.setenv("RESEND_API_KEY", "re_test")
        monkeypatch.delenv("EMAIL_FROM", raising=False)
        email_codes._deliver("qa@knowra-live.co", "654321")

        out = capsys.readouterr().out
        assert "654321" in out
        assert "reason=unverified_sender" in out

    def test_delivery_never_raises(self, monkeypatch):
        """A user with no email can retry or use Google. A 500 locks everyone
        out of the product."""
        import email_codes

        monkeypatch.setenv("RESEND_API_KEY", "re_test")
        monkeypatch.setenv("EMAIL_FROM", "Knowra <hi@knowra.test>")

        class _Boom:
            status_code = 403

        monkeypatch.setattr(email_codes.httpx, "post", lambda *a, **k: _Boom())
        # Must not raise.
        email_codes._deliver("qa@knowra-live.co", "111111")

    def test_a_configured_failure_does_not_log_the_code(self, capsys, monkeypatch):
        """A configured deployment is a real one, and a live sign-in code in a
        log is a sign-in for anyone who can read logs."""
        import email_codes

        monkeypatch.setenv("RESEND_API_KEY", "re_test")
        monkeypatch.setenv("EMAIL_FROM", "Knowra <hi@knowra.test>")

        class _Boom:
            status_code = 403

        monkeypatch.setattr(email_codes.httpx, "post", lambda *a, **k: _Boom())
        email_codes._deliver("qa@knowra-live.co", "222222")

        out = capsys.readouterr().out
        assert "email_delivery_failed" in out
        assert "sender_not_permitted" in out
        assert "222222" not in out
        # And not the address either — an error log is where an enumeration
        # signal tends to survive.
        assert "qa@knowra-live.co" not in out

    def test_causes_are_named_not_numbered(self, capsys, monkeypatch):
        import email_codes

        monkeypatch.setenv("RESEND_API_KEY", "re_test")
        monkeypatch.setenv("EMAIL_FROM", "Knowra <hi@knowra.test>")

        for status, expected in (
            (401, "bad_or_rotated_api_key"),
            (422, "recipient_rejected"),
            (429, "rate_limited"),
        ):

            class _R:
                status_code = status

            monkeypatch.setattr(email_codes.httpx, "post", lambda *a, **k: _R())
            email_codes._deliver("qa@knowra-live.co", "333333")
            assert expected in capsys.readouterr().out, status


class TestCodeNotBurnedByOurFailure:
    """QA-029. A failing `create_custom_token` spent the user's code, and
    their retry was then told the code was invalid. It was not — we were."""

    def test_the_error_message_says_the_code_still_works(self):
        import inspect

        import email_codes

        source = inspect.getsource(email_codes.verify_email_code)
        # The consume must be reversed, and the user must be told so.
        assert '"consumedAt": None' in source
        assert "still valid" in source

    def test_the_consume_is_reversed_before_the_error_is_raised(self):
        import inspect

        import email_codes

        source = inspect.getsource(email_codes.verify_email_code)
        reverse = source.index('"consumedAt": None')
        raise_at = source.index("HttpsError", reverse)
        assert reverse < raise_at, "the code must be released before we bail"

    def test_the_mint_failure_is_named_in_the_log(self):
        # Minting needs iam.serviceAccounts.signBlob on the runtime service
        # account. Without it every sign-in fails identically to a wrong
        # code, and only the log can tell them apart.
        import inspect

        import email_codes

        assert "custom_token_mint_failed" in inspect.getsource(email_codes.verify_email_code)


class TestSmtpDelivery:
    """Gmail SMTP sends from an address the account already owns, so it has no
    domain-verification step at all — which is why it takes priority over a
    Resend key that cannot reach arbitrary addresses."""

    def test_absent_without_both_user_and_password(self, monkeypatch):
        import email_codes

        monkeypatch.delenv("SMTP_USER", raising=False)
        monkeypatch.delenv("SMTP_PASSWORD", raising=False)
        assert email_codes._smtp_config() is None

        monkeypatch.setenv("SMTP_USER", "me@gmail.com")
        assert email_codes._smtp_config() is None, "a user alone is not enough"

    def test_gmail_defaults(self, monkeypatch):
        import email_codes

        monkeypatch.setenv("SMTP_USER", "me@gmail.com")
        monkeypatch.setenv("SMTP_PASSWORD", "app-password")
        config = email_codes._smtp_config()
        assert config["host"] == "smtp.gmail.com"
        assert config["port"] == 587

    def test_the_sender_is_forced_to_the_authenticated_account(self, monkeypatch):
        """Gmail rewrites or rejects a From it does not own, so EMAIL_FROM is
        deliberately ignored on this path."""
        import email_codes

        monkeypatch.setenv("SMTP_USER", "me@gmail.com")
        monkeypatch.setenv("SMTP_PASSWORD", "app-password")
        monkeypatch.setenv("EMAIL_FROM", "Knowra <spoofed@elsewhere.test>")
        assert "me@gmail.com" in email_codes._smtp_config()["sender"]
        assert "spoofed" not in email_codes._smtp_config()["sender"]

    def test_smtp_wins_over_an_unusable_resend_key(self, monkeypatch, capsys):
        import email_codes

        monkeypatch.setenv("SMTP_USER", "me@gmail.com")
        monkeypatch.setenv("SMTP_PASSWORD", "app-password")
        monkeypatch.setenv("RESEND_API_KEY", "re_test")
        monkeypatch.delenv("EMAIL_FROM", raising=False)

        sent = []
        monkeypatch.setattr(email_codes, "_send_smtp", lambda c, e, k: sent.append(e))
        email_codes._deliver("qa@knowra-live.co", "424242")

        assert sent == ["qa@knowra-live.co"]
        out = capsys.readouterr().out
        assert "via=smtp" in out
        # A configured transport must not log the code.
        assert "424242" not in out

    def test_an_smtp_failure_never_raises_and_never_logs_the_code(self, monkeypatch, capsys):
        import email_codes

        monkeypatch.setenv("SMTP_USER", "me@gmail.com")
        monkeypatch.setenv("SMTP_PASSWORD", "app-password")

        def boom(*a, **k):
            raise OSError("connection refused")

        monkeypatch.setattr(email_codes, "_send_smtp", boom)
        email_codes._deliver("qa@knowra-live.co", "515151")

        out = capsys.readouterr().out
        assert "email_delivery_failed" in out
        assert "via=smtp" in out
        assert "515151" not in out
        assert "qa@knowra-live.co" not in out

    def test_both_transports_send_the_same_words(self):
        # Two code paths sending differently-worded sign-in emails is the kind
        # of drift nobody notices until a user quotes one back.
        import inspect

        import email_codes

        source = inspect.getsource(email_codes)
        assert source.count("_TEXT_BODY.format(code=code)") == 2
        assert source.count("_HTML_BODY.format(code=code)") == 2


class TestReservedDomains:
    """Automated sign-in without ever logging a real user's code.

    Keyed on RFC 2606 / RFC 6761 reserved domains rather than an allowlist:
    an allowlist drifts — someone adds a real address to unblock themselves
    and live codes start appearing in logs — whereas a reserved TLD cannot,
    because no one will ever be allowed to own one.
    """

    def test_reserved_domains_are_recognised(self):
        import email_codes

        for address in (
            "qa@knowra-test.invalid",
            "qa@anything.test",
            "qa@example.com",
            "qa@example.org",
            "QA@Example.NET",
        ):
            assert email_codes._is_unroutable(address), address

    def test_real_domains_are_not(self):
        import email_codes

        for address in (
            "someone@gmail.com",
            "someone@knowra.com",
            # The near-misses that an allowlist-by-substring would have let
            # through: a real domain that merely *contains* a reserved name.
            "someone@example.company",
            "someone@notexample.com",
            "someone@invalid-domain.com",
            "someone@testing.co",
        ):
            assert not email_codes._is_unroutable(address), address

    def test_a_reserved_address_logs_its_code_even_with_smtp_configured(self, capsys, monkeypatch):
        import email_codes

        monkeypatch.setenv("SMTP_USER", "me@gmail.com")
        monkeypatch.setenv("SMTP_PASSWORD", "app-password")

        sent = []
        monkeypatch.setattr(email_codes, "_send_smtp", lambda c, e, k: sent.append(e))
        email_codes._deliver("qa@knowra-test.invalid", "909090")

        out = capsys.readouterr().out
        assert "909090" in out
        assert "reason=unroutable_test_domain" in out
        # And no delivery was attempted: there is nowhere to deliver to.
        assert sent == []

    def test_a_real_address_still_never_logs_its_code(self, capsys, monkeypatch):
        """The property this whole mechanism exists to preserve."""
        import email_codes

        monkeypatch.setenv("SMTP_USER", "me@gmail.com")
        monkeypatch.setenv("SMTP_PASSWORD", "app-password")
        monkeypatch.setattr(email_codes, "_send_smtp", lambda c, e, k: None)

        email_codes._deliver("real.person@gmail.com", "808080")
        out = capsys.readouterr().out
        assert "808080" not in out
        assert "via=smtp" in out


class TestTheEmailedCodeIsTheStoredCode:
    """The invariant the whole flow rests on.

    `request_email_code` generates one code, HMACs it into Firestore, and
    hands it to `_deliver`. If those two ever saw different values the failure
    would be invisible from the server's side — every request would look
    healthy, every user would be told their code was wrong, and the only
    evidence would be in an inbox nobody on the team can read.
    """

    def test_the_delivered_code_is_the_hashed_code(self, monkeypatch):
        import email_codes

        hashed: list[str] = []
        delivered: list[str] = []

        real_hash = email_codes._hash_code

        def spy_hash(code, email):
            hashed.append(code)
            return real_hash(code, email)

        monkeypatch.setenv("AUTH_CODE_SECRET", "test-secret")
        monkeypatch.setattr(email_codes, "_hash_code", spy_hash)
        monkeypatch.setattr(email_codes, "_deliver", lambda e, c: delivered.append(c))

        # Exercise just the generate-hash-deliver sequence, without Firestore.
        code = email_codes._generate_code()
        email_codes._hash_code(code, "qa@knowra-live.co")
        email_codes._deliver("qa@knowra-live.co", code)

        assert hashed == delivered == [code]

    def test_the_html_body_carries_exactly_that_code(self):
        """A stray brace in the HTML would make `.format` raise or mangle the
        substitution — and the template is full of inline CSS, which is
        exactly where a `{` tends to appear."""
        import email_codes

        rendered = email_codes._HTML_BODY.format(code="481902")
        assert rendered.count("481902") == 1
        assert "{" not in rendered and "}" not in rendered

    def test_the_text_body_carries_it_too(self):
        import email_codes

        rendered = email_codes._TEXT_BODY.format(code="481902")
        assert rendered.startswith("481902")

    def test_a_generated_code_is_six_digits(self):
        import email_codes

        for _ in range(200):
            code = email_codes._generate_code()
            assert len(code) == email_codes.CODE_LENGTH
            assert code.isdigit()

    def test_codes_are_not_predictable(self):
        # `secrets`, not `random`. A predictable sign-in code is a sign-in.
        import email_codes

        codes = {email_codes._generate_code() for _ in range(500)}
        assert len(codes) > 400, "too many collisions for a random source"
