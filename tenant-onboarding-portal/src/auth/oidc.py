"""OIDC authentication with BCGov Keycloak."""

from __future__ import annotations

from authlib.integrations.starlette_client import OAuth
from fastapi import APIRouter, Request
from fastapi.responses import RedirectResponse

from src.config import settings

router = APIRouter(prefix="/auth", tags=["auth"])

oauth = OAuth()

if settings.oidc_discovery_url:
    oauth.register(
        name="keycloak",
        client_id=settings.oidc_client_id,
        client_secret=settings.oidc_client_secret,
        server_metadata_url=settings.oidc_discovery_url,
        client_kwargs={"scope": settings.oidc_scope},
    )


@router.get("/login")
async def login(request: Request):
    if not settings.oidc_discovery_url:
        # Dev mode: auto-login as test user
        request.session["user"] = {
            "email": "dev.user@gov.bc.ca",
            "name": "Dev User",
            "preferred_username": "dev.user",
        }
        return RedirectResponse(url="/tenants/")

    redirect_uri = request.url_for("auth_callback")
    return await oauth.keycloak.authorize_redirect(request, redirect_uri)


@router.get("/callback")
async def auth_callback(request: Request):
    token = await oauth.keycloak.authorize_access_token(request)
    userinfo = token.get("userinfo", {})
    request.session["user"] = {
        "email": userinfo.get("email", ""),
        "name": userinfo.get("name", ""),
        "preferred_username": userinfo.get("preferred_username", ""),
    }
    return RedirectResponse(url="/tenants/")


@router.get("/logout")
async def logout(request: Request):
    request.session.clear()
    return RedirectResponse(url="/")
