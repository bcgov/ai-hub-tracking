"""FastAPI application entrypoint."""

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
    user = request.session.get("user")
    return templates.TemplateResponse(request, "index.html", {"user": user})
