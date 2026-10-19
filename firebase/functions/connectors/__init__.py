"""Storage connectors — architecture §9.

Import from here, not from the provider modules: the point of the package is
that callers never name a provider in code.
"""

from .base import (
    GOOGLE_DRIVE,
    ChangeSet,
    ConnectorError,
    ConnectorState,
    OAuthTokens,
    ProviderAccount,
    ProviderFile,
    ProviderFolder,
    ProviderProfile,
    ScopeLevel,
    StorageConnector,
)
from .registry import (
    PROFILES,
    REDIRECT_URI,
    ProviderNotConfigured,
    connector_for,
    is_configured,
    profile_for,
    source_url,
)

__all__ = [
    "GOOGLE_DRIVE",
    "PROFILES",
    "REDIRECT_URI",
    "ChangeSet",
    "ConnectorError",
    "ConnectorState",
    "OAuthTokens",
    "ProviderAccount",
    "ProviderFile",
    "ProviderFolder",
    "ProviderNotConfigured",
    "ProviderProfile",
    "ScopeLevel",
    "StorageConnector",
    "connector_for",
    "is_configured",
    "profile_for",
    "source_url",
]
