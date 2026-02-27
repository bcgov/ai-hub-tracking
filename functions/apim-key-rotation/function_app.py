# =============================================================================
# APIM Key Rotation — Azure Functions (Timer Trigger)
# =============================================================================
# Replaces the GitHub Actions + bash workflow for APIM subscription key
# rotation. Uses Azure SDK with Managed Identity for zero-secret operation.
#
# Timer schedule: daily at 09:00 UTC (configurable via ROTATION_CRON_SCHEDULE)
# The function checks rotation_interval_days before regenerating — most
# invocations are no-ops.
# =============================================================================

import logging
import os

import azure.functions as func

from rotation.config import Settings
from rotation.runner import run_rotation

app = func.FunctionApp()

logger = logging.getLogger("apim-key-rotation")

# Allow run_on_startup to be toggled via env var for local/Docker development.
# In production this is always False (the default).
_run_on_startup = os.getenv("RUN_ON_STARTUP", "false").lower() in ("true", "1", "yes")


@app.timer_trigger(
    schedule="%ROTATION_CRON_SCHEDULE%",
    arg_name="timer",
    run_on_startup=_run_on_startup,
)
def rotate_keys(timer: func.TimerRequest) -> None:
    """Timer-triggered APIM subscription key rotation.

    Runs daily but only regenerates keys when the rotation interval has
    elapsed.  Uses an alternating primary/secondary pattern so one key
    is always valid (zero downtime).
    """
    if timer.past_due:
        logger.warning("Timer is past due — running rotation immediately")

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
    except Exception:
        logger.exception("Key rotation failed")
        raise
