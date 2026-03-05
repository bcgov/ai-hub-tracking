"""FastAPI dependencies for authentication and authorization."""

from __future__ import annotations

from fastapi import HTTPException, Request

from src.config import settings


async def require_login(request: Request) -> dict:
    """Require an authenticated user session."""
    user = request.session.get("user")
    if not user:
        raise HTTPException(status_code=401, detail="Not authenticated. Please log in via /auth/login")
    return user


async def require_admin(request: Request) -> dict:
    """Require an authenticated admin user."""
    user = await require_login(request)
    email = user.get("email", "").lower()
    if email not in settings.admin_email_list:
        raise HTTPException(status_code=403, detail="Admin access required")
    return user
