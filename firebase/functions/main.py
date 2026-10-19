"""Knowra Cloud Functions — the whole backend.

Firebase discovers callables from this module, so everything exported here is
deployable. Implementations live in siblings to keep this a manifest.
"""

from firebase_admin import initialize_app

initialize_app()

# Imports follow initialize_app: the Admin SDK must be ready before any module
# that touches Firestore at import time.
from account_api import (
    account_summary,
    deactivate_account,
    delete_account,
    reactivate_account,
)
from api import (
    apply_retention,
    ask,
    embed_texts,
    get_subscription,
    purge_cloud_embeddings,
    search,
)
from billing_api import (
    list_products,
    restore_purchases,
    store_notification,
    verify_purchase,
)
from chunk_store import sweep_deleted_chunks
from connector_api import (
    begin_connection,
    complete_connection,
    complete_storage_setup,
    connect_device_vault,
    disconnect_account,
    list_connectors,
    list_provider_files,
    list_provider_folders,
    set_file_indexed,
    set_indexed_folders,
    set_scope_level,
)
from connector_callback import oauth_callback
from connector_sync import (
    on_index_job_created,
    sync_connected_accounts,
)
from email_codes import request_email_code, verify_email_code
from file_vault import on_memory_deleted
from ingestion import on_memory_created
from marketing import on_campaign_written, set_marketing_consent, unsubscribe
from razorpay_payments import create_razorpay_order, razorpay_webhook, verify_razorpay_payment
from reindex import reindex_backlog, reindex_memory
from retention import on_plan_changed, retention_sweep

# `on_user_created` is deliberately NOT imported.
#
# It is a blocking `beforeUserCreated` trigger, and registering one requires
# Identity Platform. On this project Firebase Auth rejects the registration
# with OPERATION_NOT_ALLOWED, which fails the whole deploy — and because the
# CLI applies Cloud Run invoker IAM as a *post-deploy phase*, an aborted
# deploy leaves every updated function returning 403 to the app. One
# unregistrable trigger silently took out email sign-in that way once already.
#
# The function itself still lives in user_lifecycle.py. Enabling Identity
# Platform and adding it back here is a one-line change; until then
# `ensure_profile` does the seeding and the trigger would never fire anyway.
from user_lifecycle import ensure_profile

__all__ = [
    # auth
    "request_email_code",
    "verify_email_code",
    "ensure_profile",
    # account
    "account_summary",
    "deactivate_account",
    "reactivate_account",
    "delete_account",
    # offers and news by email: consent, campaigns, unsubscribe
    "set_marketing_consent",
    "on_campaign_written",
    "unsubscribe",
    # connectors
    "list_connectors",
    "begin_connection",
    "complete_connection",
    "connect_device_vault",
    "set_scope_level",
    "list_provider_folders",
    "list_provider_files",
    "set_indexed_folders",
    "set_file_indexed",
    "disconnect_account",
    "complete_storage_setup",
    "oauth_callback",
    # pipeline
    "on_memory_created",
    "on_memory_deleted",
    "sweep_deleted_chunks",
    "retention_sweep",
    "on_plan_changed",
    "reindex_memory",
    "reindex_backlog",
    "on_index_job_created",
    "sync_connected_accounts",
    # on-device index: the phone embeds, the cloud forgets its vectors
    "embed_texts",
    "purge_cloud_embeddings",
    # billing
    "list_products",
    "verify_purchase",
    "restore_purchases",
    "store_notification",
    # Razorpay: rupee 30-day passes in the Android app
    "create_razorpay_order",
    "verify_razorpay_payment",
    "razorpay_webhook",
    # api
    "get_subscription",
    "search",
    "ask",
    "apply_retention",
]
