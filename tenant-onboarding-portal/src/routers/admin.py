"""Admin routes – approval dashboard, review, approve/reject."""

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
    store = TenantStore()
    pending = store.list_by_status("submitted")
    all_tenants = store.list_all_current()
    return templates.TemplateResponse(
        request, "admin_dashboard.html", {"user": user, "pending": pending, "all_tenants": all_tenants}
    )


@router.get("/review/{tenant_name}/{version}", response_class=HTMLResponse)
async def review_request(tenant_name: str, version: str, request: Request, user: dict = Depends(require_admin)):
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
    store = TenantStore()
    store.update_status(tenant_name, version, "rejected", reviewed_by=user["email"], review_notes=review_notes)
    return RedirectResponse(url="/admin/", status_code=303)
