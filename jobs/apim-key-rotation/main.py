# =============================================================================
# APIM Key Rotation — Standalone Entrypoint (Container App Job)
# =============================================================================
# Main entrypoint for running key rotation as a Container App Job.
# Scheduled via Container App Job cron trigger; runs once and exits.
# =============================================================================

import logging
import sys

from rotation.config import Settings
from rotation.runner import run_rotation

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s — %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%SZ",
    stream=sys.stdout,
)

# Suppress verbose Azure SDK HTTP loggers that dump every request/response
# header as a separate INFO-level line, creating noise in Container App logs.
for _noisy in (
    "azure.core.pipeline.policies.http_logging_policy",
    "azure.identity",
    "azure.mgmt.apimanagement",
    "azure.keyvault",
):
    logging.getLogger(_noisy).setLevel(logging.WARNING)

logger = logging.getLogger("apim-key-rotation")


def main() -> int:
    """Run key rotation and return exit code (0 = success, 1 = failure)."""
    try:
        settings = Settings()  # type: ignore[call-arg]
        logger.info(
            "Starting key rotation | env=%s app=%s interval=%d dry_run=%s",
            settings.environment,
            settings.app_name,
            settings.rotation_interval_days,
            settings.dry_run,
        )
        summary = run_rotation(settings)
        logger.info(
            "Rotation complete | total=%d rotated=%d skipped=%d failed=%d",
            summary.total,
            summary.rotated,
            summary.skipped,
            summary.failed,
        )

        if summary.failed > 0:
            logger.error("One or more tenants failed rotation")
            return 1

        return 0

    except Exception:
        logger.exception("Key rotation failed with unhandled exception")
        return 1


if __name__ == "__main__":
    sys.exit(main())
