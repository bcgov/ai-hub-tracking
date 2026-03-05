"""Admin routes – approval dashboard, review, approve/reject.

All routes require admin privileges enforced by ``require_admin``, which
checks the user's Keycloak roles (primary) and the email allow-list (fallback).
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates

from src.auth.dependencies import require_admin
from src.storage.table_storage import TenantStore

router = APIRouter(prefix="/admin", tags=["admin"])
templates = Jinja2Templates(directory="src/templates")


@router.get("/", response_class=HTMLResponse)
async def admin_dashboard(request: Request, user: dict = Depends(require_admin)):
    """Render the admin overview dashboard.

    Shows two sections:
    * **Pending approvals** — requests with ``status = "submitted"``
    * **All tenants** — the current registry of every known tenant

    Parameters
    ----------
    request:
        The incoming HTTP request.
    user:
        The authenticated admin user dict (injected by ``require_admin``).

    Returns
    -------
    HTMLResponse
        Rendered ``admin_dashboard.html`` template.
    """
    store = TenantStore()
    pending = store.list_by_status("submitted")
    all_tenants = store.list_all_current()
    return templates.TemplateResponse(
        request, "admin_dashboard.html", {"user": user, "pending": pending, "all_tenants": all_tenants}
    )


@router.get("/review/{tenant_name}/{version}", response_class=HTMLResponse)
async def review_request(tenant_name: str, version: str, request: Request, user: dict = Depends(require_admin)):
    """Render the side-by-side review page for a specific request version.

    Displays the raw form data alongside the generated HCL tfvars for the
    admin to evaluate before approving or rejecting.

    Parameters
    ----------
    tenant_name:
        Tenant identifier from the URL path.
    version:
        Version key (e.g. ``"v1"``).
    request:
        The incoming HTTP request.
    user:
        The authenticated admin user dict.

    Returns
    -------
    HTMLResponse
        Rendered ``admin_review.html`` template.
    """
    store = TenantStore()
    tenant_request = store.get_version(tenant_name, version)
    return templates.TemplateResponse(
        request, "admin_review.html", {"user": user, "tenant_request": tenant_request}
    )


@router.post("/approve/{tenant_name}/{version}")
async def approve_request(
    tenant_name: str,
    version: str,
    request: Request,
    review_notes: str = Form(""),
    user: dict = Depends(require_admin),
):
    """Approve a pending tenant request.

    Updates the request status to ``"approved"``, records the reviewer's
    email and any notes, then redirects to the admin dashboard.

    Parameters
    ----------
    tenant_name:
        Tenant identifier.
    version:
        Version key to approve.
    request:
        The incoming POST request.
    review_notes:
        Optional free-text notes from the admin (from the review form).
    user:
        The authenticated admin user dict.

    Returns
    -------
    RedirectResponse
        303 redirect to ``/admin/``.
    """
    store = TenantStore()
    store.update_status(tenant_name, version, "approved", reviewed_by=user["email"], review_notes=review_notes)
    return RedirectResponse(url="/admin/", status_code=303)


@router.post("/reject/{tenant_name}/{version}")
async def reject_request(
    tenant_name: str,
    version: str,
    request: Request,
    review_notes: str = Form(""),
    user: dict = Depends(require_admin),
):
    """Reject a pending tenant request.

    Updates the request status to ``"rejected"``, records the reviewer's
    email and mandatory notes, then redirects to the admin dashboard.

    Parameters
    ----------
    tenant_name:
        Tenant identifier.
    version:
        Version key to reject.
    request:
        The incoming POST request.
    review_notes:
        Reason for rejection (strongly recommended so tenants can act on it).
    user:
        The authenticated admin user dict.

    Returns
    -------
    RedirectResponse
        303 redirect to ``/admin/``.
    """
    store = TenantStore()
    store.update_status(tenant_name, version, "rejected", reviewed_by=user["email"], review_notes=review_notes)
    return RedirectResponse(url="/admin/", status_code=303)
