"""Tenant CRUD routes – create, update, view projects."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates

from src.auth.dependencies import require_login
from src.models.form_schema import FORM_SCHEMA
from src.models.tenant import TenantFormData
from src.services.tfvars_generator import generate_all_env_tfvars
from src.storage.table_storage import TenantStore

router = APIRouter(prefix="/tenants", tags=["tenants"])
templates = Jinja2Templates(directory="src/templates")


@router.get("/", response_class=HTMLResponse)
async def dashboard(request: Request, user: dict = Depends(require_login)):
    store = TenantStore()
    my_tenants = store.list_by_user(user["email"])
    return templates.TemplateResponse(request, "dashboard.html", {"user": user, "tenants": my_tenants})


@router.get("/new", response_class=HTMLResponse)
async def new_tenant_form(request: Request, user: dict = Depends(require_login)):
    return templates.TemplateResponse(
        request, "tenant_form.html", {"user": user, "form_schema": FORM_SCHEMA, "mode": "create", "values": {}}
    )


@router.post("/new")
async def create_tenant(request: Request, user: dict = Depends(require_login)):
    form = await request.form()
    data = TenantFormData.from_form(dict(form))

    tfvars = generate_all_env_tfvars(data)

    store = TenantStore()
    store.create_request(
        tenant_name=data.project_name,
        display_name=data.display_name,
        form_data=data.model_dump(),
        generated_tfvars=tfvars,
        submitted_by=user["email"],
    )
    return RedirectResponse(url=f"/tenants/{data.project_name}", status_code=303)


@router.get("/{tenant_name}", response_class=HTMLResponse)
async def tenant_detail(tenant_name: str, request: Request, user: dict = Depends(require_login)):
    store = TenantStore()
    tenant = store.get_current(tenant_name)
    versions = store.list_versions(tenant_name)
    return templates.TemplateResponse(
        request, "tenant_detail.html", {"user": user, "tenant": tenant, "versions": versions}
    )


@router.get("/{tenant_name}/edit", response_class=HTMLResponse)
async def edit_tenant_form(tenant_name: str, request: Request, user: dict = Depends(require_login)):
    store = TenantStore()
    tenant = store.get_current(tenant_name)
    if not tenant:
        return RedirectResponse(url="/tenants/", status_code=303)
    return templates.TemplateResponse(
        request,
        "tenant_form.html",
        {"user": user, "form_schema": FORM_SCHEMA, "mode": "edit", "values": tenant.get("FormData", {})},
    )


@router.post("/{tenant_name}/edit")
async def update_tenant(tenant_name: str, request: Request, user: dict = Depends(require_login)):
    form = await request.form()
    data = TenantFormData.from_form(dict(form))

    tfvars = generate_all_env_tfvars(data)

    store = TenantStore()
    store.create_request(
        tenant_name=tenant_name,
        display_name=data.display_name,
        form_data=data.model_dump(),
        generated_tfvars=tfvars,
        submitted_by=user["email"],
    )
    return RedirectResponse(url=f"/tenants/{tenant_name}", status_code=303)
