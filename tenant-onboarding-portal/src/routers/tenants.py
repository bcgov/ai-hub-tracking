"""Tenant CRUD routes – create, update, and view projects.

All routes require an authenticated user session (``require_login``).
Tenant ownership is not enforced at the route level — any authenticated
BCGov user can view any tenant — but the dashboard filters by submitter email
so each user sees their own projects by default.
"""

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
    """Render the authenticated user's project dashboard.

    Queries the store for all requests submitted by the current user and
    renders the dashboard template.  Each row in the list links to the
    tenant detail page for that project.

    Parameters
    ----------
    request:
        The incoming HTTP request.
    user:
        The authenticated session user dict (injected by ``require_login``).

    Returns
    -------
    HTMLResponse
        Rendered ``dashboard.html`` template.
    """
    store = TenantStore()
    my_tenants = store.list_by_user(user["email"])
    return templates.TemplateResponse(request, "dashboard.html", {"user": user, "tenants": my_tenants})


@router.get("/new", response_class=HTMLResponse)
async def new_tenant_form(request: Request, user: dict = Depends(require_login)):
    """Render the blank tenant creation form.

    Parameters
    ----------
    request:
        The incoming HTTP request.
    user:
        The authenticated session user dict.

    Returns
    -------
    HTMLResponse
        Rendered ``tenant_form.html`` in ``create`` mode with an empty values dict.
    """
    return templates.TemplateResponse(
        request, "tenant_form.html", {"user": user, "form_schema": FORM_SCHEMA, "mode": "create", "values": {}}
    )


@router.post("/new")
async def create_tenant(request: Request, user: dict = Depends(require_login)):
    """Handle new tenant form submission.

    Parses and validates form data, generates tfvars for all three
    environments, persists the request as ``v1``, and redirects to the
    tenant detail page.

    Parameters
    ----------
    request:
        The incoming POST request with multipart form data.
    user:
        The authenticated session user dict.

    Returns
    -------
    RedirectResponse
        303 redirect to the new tenant's detail page on success.

    Raises
    ------
    pydantic.ValidationError
        Propagated as HTTP 422 by FastAPI if form data fails validation.
    """
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
    """Render the detail page for a specific tenant.

    Shows the current configuration, generated tfvars preview, and version
    history.  Accessible to all authenticated users (not admin-gated).

    Parameters
    ----------
    tenant_name:
        The tenant's ``project_name`` identifier from the URL path.
    request:
        The incoming HTTP request.
    user:
        The authenticated session user dict.

    Returns
    -------
    HTMLResponse
        Rendered ``tenant_detail.html`` template.
    """
    store = TenantStore()
    tenant = store.get_current(tenant_name)
    versions = store.list_versions(tenant_name)
    return templates.TemplateResponse(
        request, "tenant_detail.html", {"user": user, "tenant": tenant, "versions": versions}
    )


@router.get("/{tenant_name}/edit", response_class=HTMLResponse)
async def edit_tenant_form(tenant_name: str, request: Request, user: dict = Depends(require_login)):
    """Render the pre-populated edit form for an existing tenant.

    Loads the current version's ``FormData`` and pre-fills the form so the
    user only needs to change the fields they want to update.

    Parameters
    ----------
    tenant_name:
        The tenant's ``project_name`` identifier from the URL path.
    request:
        The incoming HTTP request.
    user:
        The authenticated session user dict.

    Returns
    -------
    HTMLResponse | RedirectResponse
        Rendered ``tenant_form.html`` in ``edit`` mode, or a 303 redirect
        to the dashboard if the tenant does not exist.
    """
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
    """Handle tenant update form submission.

    Creates a new version of the request (e.g. ``v2``, ``v3``) with
    ``status = "submitted"``, regenerates tfvars, and redirects to the
    detail page.  The previous version is preserved for audit purposes.

    Parameters
    ----------
    tenant_name:
        The tenant's ``project_name`` identifier from the URL path.
    request:
        The incoming POST request with multipart form data.
    user:
        The authenticated session user dict.

    Returns
    -------
    RedirectResponse
        303 redirect to the tenant detail page.
    """
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
