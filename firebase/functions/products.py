"""The things a user can buy, and how a store's word becomes an entitlement.

One list, shared by both stores and by the client, because a product id
mismatch is silent: the purchase succeeds, the receipt validates, and the
tier never changes — the worst possible failure, since the user has paid.

The ids are deliberately verbose. Both stores make them permanent and
non-reusable, so a name has to survive a pricing change: `knowra.standard.
monthly` is still correct after $9 becomes $11, where `knowra.nine` is not.
"""

from __future__ import annotations

from dataclasses import dataclass

from billing import PREMIUM, STANDARD


@dataclass(frozen=True, slots=True)
class Product:
    product_id: str
    tier: str
    #: Months of access one purchase grants. Used to derive the period end
    #: when a store gives a start but not an expiry.
    months: int
    #: Google groups subscriptions under one id with base plans; Apple uses a
    #: subscription group. Both are recorded so validation can check the
    #: purchase came from the product we think it did.
    google_base_plan: str | None = None
    #: The price the paywall shows *until the store can*. The store's own
    #: localised price always wins once it lists the product; this exists so
    #: the paywall is a real price screen before the consoles are set up, and
    #: on devices with no store. Keep it equal to what the stores charge.
    reference_price: str | None = None
    reference_amount: float = 0.0
    currency: str = "USD"
    #: Price of a 30-day Razorpay pass in the Android app, in paise
    #: (`razorpay_payments`). The only rupee price anywhere: the app is shown
    #: it and the order is created at it, never at a price the app sends.
    inr_paise: int | None = None


#: Keyed by store product id.
#:
#: **Monthly only (2026-09-27 decision).** No annual plans: the app lists
#: exactly what this table holds, so removing a product here removes it from
#: the paywall. `months` stays on `Product` so an annual plan is a two-line
#: change if it ever comes back.
CATALOGUE: dict[str, Product] = {
    "knowra.standard.monthly": Product(
        "knowra.standard.monthly",
        STANDARD,
        1,
        google_base_plan="standard-monthly",
        reference_price="$4.99",
        reference_amount=4.99,
        inr_paise=19_900,
    ),
    "knowra.premium.monthly": Product(
        "knowra.premium.monthly",
        PREMIUM,
        1,
        google_base_plan="premium-monthly",
        reference_price="$9.99",
        reference_amount=9.99,
        inr_paise=39_900,
    ),
}


def product_for(product_id: str) -> Product | None:
    return CATALOGUE.get(product_id)


def ids() -> list[str]:
    return sorted(CATALOGUE)
