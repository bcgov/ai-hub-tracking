# =============================================================================
# Configuration — Pydantic Settings loaded from environment variables
# =============================================================================
from __future__ import annotations

from pydantic import Field
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Application settings resolved from environment variables.

    Every setting maps 1:1 to an env var configured by Terraform on the
    Container App Job.
    """

    model_config = {"env_prefix": "", "case_sensitive": False}

    # Required — set by Terraform for each environment
    environment: str = Field(description="Target environment (dev, test, prod)")
    app_name: str = Field(description="Application name prefix (e.g. ai-services-hub)")
    subscription_id: str = Field(description="Azure subscription ID")

    # Derived from naming convention unless overridden
    resource_group: str = Field(default="", description="Resource group override (default: {app_name}-{environment})")
    apim_name: str = Field(
        default="",
        description="APIM instance name override (default: {app_name}-{environment}-apim)",
    )
    hub_keyvault_name: str = Field(
        default="",
        description="Hub Key Vault name override (default: {app_name}-{environment}-hkv)",
    )

    # Rotation behaviour
    rotation_enabled: bool = Field(default=True, description="Master rotation toggle")
    rotation_interval_days: int = Field(default=7, ge=1, le=89, description="Days between rotations (must be < 90)")
    dry_run: bool = Field(default=False, description="Show what would happen without making changes")

    # Key Vault secret expiry (days) — Azure Landing Zone policy requires max 90 days
    secret_expiry_days: int = Field(default=90, ge=1, le=365, description="Days until Key Vault secrets expire")

    # ---------------------------------------------------------------------------
    # Derived defaults applied after model init
    # ---------------------------------------------------------------------------
    def model_post_init(self, __context: object) -> None:
        if not self.resource_group:
            self.resource_group = f"{self.app_name}-{self.environment}"
        if not self.apim_name:
            self.apim_name = f"{self.app_name}-{self.environment}-apim"
        if not self.hub_keyvault_name:
            self.hub_keyvault_name = f"{self.app_name}-{self.environment}-hkv"
