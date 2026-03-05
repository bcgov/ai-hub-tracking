"""Health check endpoint.

Provides a simple liveness probe at ``/healthz`` used by:
* Azure App Service health checks (configured in the portal)
* The deployment workflow's post-deploy verification step
* Load balancers and monitoring tools
"""

from __future__ import annotations

from fastapi import APIRouter

router = APIRouter(tags=["health"])


@router.get("/healthz", summary="Liveness probe")
async def healthz():
    """Return HTTP 200 with a static JSON body.

    This endpoint intentionally avoids any external dependencies (database,
    OIDC, storage) so that it reliably indicates whether the Python process
    is alive, not whether downstream services are healthy.

    Returns
    -------
    dict
        ``{"status": "ok"}``
    """
    return {"status": "ok"}
