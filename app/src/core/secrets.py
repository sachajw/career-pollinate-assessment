"""Azure Key Vault secret retrieval with in-memory caching.

Uses DefaultAzureCredential which supports:
- Managed Identity (when running in Azure Container Apps)
- Azure CLI credentials (local development with `az login`)
- Environment credentials (CI/CD with service principal env vars)
"""

import time

import structlog
from azure.core.exceptions import AzureError
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

logger = structlog.get_logger()

# In-memory cache: {vault_url:secret_name -> (value, expiry_monotonic)}
_cache: dict[str, tuple[str, float]] = {}
_CACHE_TTL = 300  # 5 minutes, as documented in solution-architecture.md


def get_key_vault_secret(vault_url: str, secret_name: str) -> str:
    """Retrieve a secret from Azure Key Vault.

    Uses in-memory cache with 5-minute TTL to reduce Key Vault API calls
    and stay within free-tier operation limits.

    Authenticates via DefaultAzureCredential:
    - In Azure: uses system-assigned Managed Identity (no credentials needed)
    - Locally: uses `az login` credentials or AZURE_* environment variables

    Args:
        vault_url: Key Vault URL, e.g. https://kv-finrisk-dev.vault.azure.net/
        secret_name: Name of the secret to retrieve (e.g. RISKSHIELD-API-KEY)

    Returns:
        The secret value as a string

    Raises:
        AzureError: If the secret cannot be retrieved from Key Vault
    """
    now = time.monotonic()
    cache_key = f"{vault_url}:{secret_name}"

    if cache_key in _cache:
        value, expiry = _cache[cache_key]
        if now < expiry:
            logger.debug("Key Vault cache hit", secret_name=secret_name)
            return value

    logger.info("Fetching secret from Key Vault", secret_name=secret_name, vault_url=vault_url)

    try:
        credential = DefaultAzureCredential()
        client = SecretClient(vault_url=vault_url, credential=credential)
        secret = client.get_secret(secret_name)
        value = secret.value

        _cache[cache_key] = (value, now + _CACHE_TTL)
        logger.info("Secret retrieved from Key Vault", secret_name=secret_name)
        return value

    except AzureError as e:
        logger.error(
            "Failed to retrieve secret from Key Vault",
            secret_name=secret_name,
            vault_url=vault_url,
            error=str(e),
        )
        raise
