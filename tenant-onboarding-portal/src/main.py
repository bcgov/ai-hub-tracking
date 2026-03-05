"""FastAPI application entrypoint for the Tenant Onboarding Portal.

Assembles the ASGI application by:
* Registering ``SessionMiddleware`` with the configured secret key.
* Mounting the ``/static`` directory for CSS/JS assets.
* Configuring the Jinja2 template engine.
* Including all route modules: auth, tenants, admin, health.

The Swagger UI (``/api/docs``) is only enabled when ``PORTAL_DEBUG=true`` to
avoid exposing the API schema in production.

Startup command (App Service / local):
    ``gunicorn -w 2 -k uvicorn.workers.UvicornWorker src.main:app``
"""

from __future__ import annotations

from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from starlette.middleware.sessions import SessionMiddleware

from src.auth.oidc import router as auth_router
from src.config import settings
from src.routers import admin, health, tenants

app = FastAPI(
    title=settings.app_name,
    docs_url="/api/docs" if settings.debug else None,
    redoc_url=None,
)

app.add_middleware(SessionMiddleware, secret_key=settings.secret_key)

# --- Static files & templates ---
app.mount("/static", StaticFiles(directory="src/static"), name="static")
templates = Jinja2Templates(directory="src/templates")

# --- Routers ---
app.include_router(health.router)
app.include_router(auth_router)
app.include_router(tenants.router)
app.include_router(admin.router)


@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    """Render the public landing page.

    Displays a welcome page with a login button.  If the user already has an
    active session their name is shown in the navigation bar (via the base
    template).  No authentication is required for this route.

    Parameters
    ----------
    request:
        The incoming HTTP request.

    Returns
    -------
    HTMLResponse
        Rendered ``index.html`` template with the optional ``user`` context
        variable (``None`` if not logged in).
    """
    user = request.session.get("user")
    return templates.TemplateResponse(request, "index.html", {"user": user})
