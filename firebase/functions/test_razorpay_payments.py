"""Razorpay 30-day passes (`razorpay_payments`)."""

import hashlib
import hmac
from datetime import UTC, datetime, timedelta

import billing
import products
import razorpay_payments as rp

NOW = datetime(2026, 10, 14, 12, 0, tzinfo=UTC)
SECRET = "test_secret"


def _sign(order_id: str, payment_id: str, secret: str = SECRET) -> str:
    return hmac.new(
        secret.encode(), f"{order_id}|{payment_id}".encode(), hashlib.sha256
    ).hexdigest()


class TestPrices:
    def test_the_server_sets_the_price_in_paise(self):
        assert rp.price_paise("knowra.standard.monthly") == 19_900
        assert rp.price_paise("knowra.premium.monthly") == 39_900

    def test_an_unknown_product_has_no_price(self):
        assert rp.price_paise("knowra.everything.forever") is None

    def test_every_priced_product_is_in_the_catalogue(self):
        for product_id, paise in rp.PRICES_PAISE.items():
            assert products.product_for(product_id) is not None
            assert paise >= rp.MIN_PAISE


class TestSignature:
    def test_razorpays_signature_is_accepted(self):
        assert rp.signature_valid("order_1", "pay_1", _sign("order_1", "pay_1"), SECRET)

    def test_a_signature_for_another_payment_is_refused(self):
        assert not rp.signature_valid("order_1", "pay_2", _sign("order_1", "pay_1"), SECRET)

    def test_a_signature_made_with_another_secret_is_refused(self):
        assert not rp.signature_valid("order_1", "pay_1", _sign("order_1", "pay_1", "x"), SECRET)

    def test_missing_pieces_are_refused(self):
        assert not rp.signature_valid("", "pay_1", "abc", SECRET)
        assert not rp.signature_valid("order_1", "pay_1", "", SECRET)
        assert not rp.signature_valid("order_1", "pay_1", _sign("order_1", "pay_1"), "")


class TestPeriod:
    def test_a_first_pass_runs_thirty_days(self):
        assert rp.period_end(None, billing.STANDARD, NOW) == NOW + timedelta(days=30)

    def test_paying_early_for_the_same_plan_adds_on(self):
        current = {
            "tier": billing.STANDARD,
            "status": "active",
            "currentPeriodEnd": NOW + timedelta(days=10),
        }
        assert rp.period_end(current, billing.STANDARD, NOW) == NOW + timedelta(days=40)

    def test_an_expired_plan_starts_again_from_now(self):
        current = {
            "tier": billing.STANDARD,
            "status": "active",
            "currentPeriodEnd": NOW - timedelta(days=1),
        }
        assert rp.period_end(current, billing.STANDARD, NOW) == NOW + timedelta(days=30)

    def test_switching_plans_starts_from_now(self):
        current = {
            "tier": billing.STANDARD,
            "status": "active",
            "currentPeriodEnd": (NOW + timedelta(days=10)).isoformat(),
        }
        assert rp.period_end(current, billing.PREMIUM, NOW) == NOW + timedelta(days=30)


class TestStoreClash:
    def test_a_running_auto_renewing_store_plan_blocks_a_pass(self):
        current = {
            "store": "google",
            "autoRenewing": True,
            "currentPeriodEnd": NOW + timedelta(days=5),
        }
        assert rp.blocks_purchase(current, NOW)

    def test_a_cancelled_or_expired_store_plan_does_not(self):
        cancelled = {"store": "google", "autoRenewing": False, "currentPeriodEnd": NOW}
        expired = {
            "store": "google",
            "autoRenewing": True,
            "currentPeriodEnd": NOW - timedelta(days=1),
        }
        assert not rp.blocks_purchase(cancelled, NOW)
        assert not rp.blocks_purchase(expired, NOW)

    def test_an_earlier_pass_or_no_plan_does_not(self):
        assert not rp.blocks_purchase(None, NOW)
        assert not rp.blocks_purchase({"store": "razorpay", "autoRenewing": False}, NOW)


class TestGrantedPass:
    def test_a_pass_is_an_ordinary_non_renewing_subscription(self):
        product = products.product_for("knowra.premium.monthly")
        end = NOW + timedelta(days=30)
        verified = rp.verified_pass(product, "pay_9", 39_900, end, NOW)
        assert verified.tier == billing.PREMIUM
        assert verified.store == "razorpay"
        assert verified.auto_renewing is False
        assert verified.period_end == end
        assert verified.transaction_id == "pay_9"
        assert verified.receipt.amount_micros == 399 * 1_000_000
        assert verified.receipt.currency == "INR"


class TestWebhook:
    BODY = b'{"event":"payment.captured"}'

    def test_razorpays_signature_on_the_raw_body_is_accepted(self):
        sig = hmac.new(b"whsec", self.BODY, hashlib.sha256).hexdigest()
        assert rp.webhook_signature_valid(self.BODY, sig, "whsec")

    def test_a_changed_body_or_secret_is_refused(self):
        sig = hmac.new(b"whsec", self.BODY, hashlib.sha256).hexdigest()
        assert not rp.webhook_signature_valid(self.BODY + b" ", sig, "whsec")
        assert not rp.webhook_signature_valid(self.BODY, sig, "other")
        assert not rp.webhook_signature_valid(self.BODY, "", "whsec")
        assert not rp.webhook_signature_valid(b"", sig, "whsec")

    def test_the_payload_entities_are_read(self):
        event = {"payload": {"payment": {"entity": {"id": "pay_1"}}}}
        assert rp._entity(event, "payment") == {"id": "pay_1"}
        assert rp._entity(event, "refund") == {}

    def test_a_captured_payment_must_pay_the_whole_order(self):
        order = {"amount": 19_900}
        good = {"status": "captured", "amount": 19_900, "currency": "INR"}
        assert rp.captured_for_order(good, order)
        assert not rp.captured_for_order({**good, "amount": 100}, order)
        assert not rp.captured_for_order({**good, "status": "authorized"}, order)
        assert not rp.captured_for_order({**good, "currency": "USD"}, order)

    def test_only_a_full_refund_ends_a_pass(self):
        order = {"amount": 39_900}
        assert rp.full_refund({"amount": 39_900}, order)
        assert not rp.full_refund({"amount": 10_000}, order)
