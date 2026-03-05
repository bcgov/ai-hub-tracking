"""Azure Table Storage client – CRUD + versioning for tenant requests.

Two Azure Table Storage tables are used:

``TenantRequests``
    One row per submission version.
    ``PartitionKey = tenant_name``, ``RowKey = v1 | v2 | ...``

``TenantRegistry``
    Pointer to the current active version for quick lookups.
    ``PartitionKey = tenant_name``, ``RowKey = "current"``

Authentication
--------------
When ``PORTAL_TABLE_STORAGE_ACCOUNT_URL`` is set, the client uses
``DefaultAzureCredential`` (managed identity on App Service, OIDC/CLI locally).
When ``PORTAL_TABLE_STORAGE_CONNECTION_STRING`` is set, it is used directly
(useful for Azurite local emulation or connection-string-based access).
When neither is configured, an **in-memory dict** is used as a fallback so
that tests and local development work without any Azure credentials.
"""

from __future__ import annotations

import json
from datetime import UTC, datetime
from typing import Any

from azure.data.tables import TableClient, TableServiceClient

from src.config import settings

REQUESTS_TABLE = "TenantRequests"
REGISTRY_TABLE = "TenantRegistry"


class TenantStore:
    """Thin wrapper around Azure Table Storage for tenant request persistence.

    All public methods work identically whether backed by Azure Table Storage
    or the in-memory fallback, enabling seamless local development.
    """

    def __init__(self) -> None:
        """Initialise the store, choosing a backend based on configuration.

        Backend selection order:
        1. Connection string (``PORTAL_TABLE_STORAGE_CONNECTION_STRING``)
        2. Account URL + ``DefaultAzureCredential`` (managed identity / CLI)
        3. In-memory dict (no Azure credentials — dev / tests only)
        """
        if settings.table_storage_connection_string:
            self._service = TableServiceClient.from_connection_string(settings.table_storage_connection_string)
        elif settings.table_storage_account_url:
            from azure.identity import DefaultAzureCredential

            self._service = TableServiceClient(
                endpoint=settings.table_storage_account_url, credential=DefaultAzureCredential()
            )
        else:
            # In-memory fallback for local dev without Azure
            self._service = None
            self._memory: dict[str, dict[str, dict]] = {REQUESTS_TABLE: {}, REGISTRY_TABLE: {}}

    def _ensure_tables(self) -> None:
        """Create the TenantRequests and TenantRegistry tables if they do not exist.

        Safe to call multiple times; Table Storage upserts the table
        definition idempotently.  No-op when the in-memory backend is active.
        """
        if self._service:
            self._service.create_table_if_not_exists(REQUESTS_TABLE)
            self._service.create_table_if_not_exists(REGISTRY_TABLE)

    def _requests_table(self) -> TableClient | None:
        """Return a TableClient for TenantRequests, or None for in-memory mode."""
        if self._service:
            self._ensure_tables()
            return self._service.get_table_client(REQUESTS_TABLE)
        return None

    def _registry_table(self) -> TableClient | None:
        """Return a TableClient for TenantRegistry, or None for in-memory mode."""
        if self._service:
            self._ensure_tables()
            return self._service.get_table_client(REGISTRY_TABLE)
        return None

    # ---- Write operations ----

    def create_request(
        self,
        tenant_name: str,
        display_name: str,
        form_data: dict[str, Any],
        generated_tfvars: dict[str, str],
        submitted_by: str,
    ) -> str:
        """Persist a new tenant request version and update the registry pointer.

        The version key is auto-incremented (``v1``, ``v2``, …) by reading
        the existing version list.  Both the TenantRequests row and the
        TenantRegistry pointer are written atomically via individual upserts
        (Table Storage does not support cross-table transactions).

        Parameters
        ----------
        tenant_name:
            Unique tenant identifier (``project_name`` from the form).
        display_name:
            Human-readable project display name.
        form_data:
            Serialisable dict of the form values (from ``model.model_dump()``).
        generated_tfvars:
            Dict mapping ``{"dev": "<hcl>", "test": "<hcl>", "prod": "<hcl>"}``.
        submitted_by:
            Email address of the authenticated user who submitted the form.

        Returns
        -------
        str
            The new version key (e.g. ``"v3"``).
        """
        next_version = self._next_version(tenant_name)
        now = datetime.now(UTC).isoformat()

        entity = {
            "PartitionKey": tenant_name,
            "RowKey": next_version,
            "DisplayName": display_name,
            "Ministry": form_data.get("ministry", ""),
            "FormData": json.dumps(form_data),
            "GeneratedTfvars": json.dumps(generated_tfvars),
            "Status": "submitted",
            "SubmittedBy": submitted_by,
            "ReviewedBy": "",
            "ReviewNotes": "",
            "FormVersion": form_data.get("form_version", ""),
            "CreatedAt": now,
            "UpdatedAt": now,
        }

        table = self._requests_table()
        if table:
            table.upsert_entity(entity)
        else:
            key = f"{tenant_name}:{next_version}"
            self._memory[REQUESTS_TABLE][key] = entity

        # Update registry
        self._upsert_registry(tenant_name, next_version)
        return next_version

    def update_status(
        self,
        tenant_name: str,
        version: str,
        status: str,
        reviewed_by: str = "",
        review_notes: str = "",
    ) -> None:
        """Update the status of a specific request version.

        Used by admin routes to approve or reject a pending submission.
        Only the ``Status``, ``ReviewedBy``, ``ReviewNotes``, and
        ``UpdatedAt`` fields are modified; all other fields remain unchanged.

        Parameters
        ----------
        tenant_name:
            Tenant identifier (``PartitionKey``).
        version:
            Version key such as ``"v1"`` (``RowKey``).
        status:
            Target status — must be a valid transition per
            :func:`~src.services.approval.can_transition`.
        reviewed_by:
            Email of the admin who performed the review.
        review_notes:
            Optional free-text notes from the reviewer.
        """
        now = datetime.now(UTC).isoformat()
        table = self._requests_table()
        if table:
            entity = table.get_entity(tenant_name, version)
            entity["Status"] = status
            entity["ReviewedBy"] = reviewed_by
            entity["ReviewNotes"] = review_notes
            entity["UpdatedAt"] = now
            table.upsert_entity(entity)
        else:
            key = f"{tenant_name}:{version}"
            if key in self._memory[REQUESTS_TABLE]:
                self._memory[REQUESTS_TABLE][key]["Status"] = status
                self._memory[REQUESTS_TABLE][key]["ReviewedBy"] = reviewed_by
                self._memory[REQUESTS_TABLE][key]["ReviewNotes"] = review_notes
                self._memory[REQUESTS_TABLE][key]["UpdatedAt"] = now

    # ---- Read operations ----

    def get_current(self, tenant_name: str) -> dict | None:
        """Return the most recent request version for a tenant.

        Reads the registry pointer to find the current version key, then
        fetches that specific row from TenantRequests.

        Parameters
        ----------
        tenant_name:
            Tenant identifier.

        Returns
        -------
        dict | None
            Deserialised entity dict, or ``None`` if no record exists.
        """
        reg = self._get_registry(tenant_name)
        if not reg:
            return None
        return self.get_version(tenant_name, reg["CurrentVersion"])

    def get_version(self, tenant_name: str, version: str) -> dict | None:
        """Fetch a specific request version by tenant name and version key.

        Parameters
        ----------
        tenant_name:
            Tenant identifier (``PartitionKey``).
        version:
            Version key such as ``"v2"`` (``RowKey``).

        Returns
        -------
        dict | None
            Deserialised entity dict, or ``None`` if not found.
        """
        table = self._requests_table()
        if table:
            try:
                entity = table.get_entity(tenant_name, version)
                return self._deserialize(entity)
            except Exception:
                return None
        else:
            key = f"{tenant_name}:{version}"
            entity = self._memory[REQUESTS_TABLE].get(key)
            return self._deserialize(entity) if entity else None

    def list_versions(self, tenant_name: str) -> list[dict]:
        """Return all request versions for a tenant, newest first.

        Parameters
        ----------
        tenant_name:
            Tenant identifier (``PartitionKey``).

        Returns
        -------
        list[dict]
            List of deserialised entity dicts sorted by ``RowKey`` descending.
        """
        table = self._requests_table()
        if table:
            entities = table.query_entities(f"PartitionKey eq '{tenant_name}'")
            return sorted([self._deserialize(e) for e in entities], key=lambda x: x.get("RowKey", ""), reverse=True)
        else:
            return sorted(
                [
                    self._deserialize(v)
                    for k, v in self._memory[REQUESTS_TABLE].items()
                    if k.startswith(f"{tenant_name}:")
                ],
                key=lambda x: x.get("RowKey", ""),
                reverse=True,
            )

    def list_by_user(self, email: str) -> list[dict]:
        """Return all request versions submitted by a specific user.

        Parameters
        ----------
        email:
            The submitter's email address.  Comparison is case-insensitive.

        Returns
        -------
        list[dict]
            All request entity dicts where ``SubmittedBy`` matches.
        """
        table = self._requests_table()
        email_lower = email.lower()
        if table:
            entities = table.query_entities(f"SubmittedBy eq '{email_lower}'")
            return [self._deserialize(e) for e in entities]
        else:
            return [
                self._deserialize(v)
                for v in self._memory[REQUESTS_TABLE].values()
                if v.get("SubmittedBy", "").lower() == email_lower
            ]

    def list_by_status(self, status: str) -> list[dict]:
        """Return all request versions that match a given status.

        Used by the admin dashboard to show pending submissions.

        Parameters
        ----------
        status:
            Status value to filter on (e.g. ``"submitted"``, ``"approved"``).

        Returns
        -------
        list[dict]
            All matching request entity dicts.
        """
        table = self._requests_table()
        if table:
            entities = table.query_entities(f"Status eq '{status}'")
            return [self._deserialize(e) for e in entities]
        else:
            return [
                self._deserialize(v) for v in self._memory[REQUESTS_TABLE].values() if v.get("Status") == status
            ]

    def list_all_current(self) -> list[dict]:
        """Return the current (latest) version of every known tenant.

        Iterates the TenantRegistry table and fetches the corresponding row
        from TenantRequests for each entry.  Used by the admin dashboard to
        display the full tenant inventory.

        Returns
        -------
        list[dict]
            List of current-version entity dicts for all tenants.
        """
        reg_table = self._registry_table()
        results = []
        if reg_table:
            for reg in reg_table.list_entities():
                tenant = self.get_version(reg["PartitionKey"], reg.get("CurrentVersion", "v1"))
                if tenant:
                    results.append(tenant)
        else:
            for v in self._memory[REGISTRY_TABLE].values():
                tenant = self.get_version(v["PartitionKey"], v.get("CurrentVersion", "v1"))
                if tenant:
                    results.append(tenant)
        return results

    # ---- Internal helpers ----

    def _next_version(self, tenant_name: str) -> str:
        """Calculate the next sequential version key for a tenant.

        Reads all existing versions, parses the integer suffix from each
        ``RowKey`` (e.g. ``"v3"`` → 3), and returns the next value.

        Parameters
        ----------
        tenant_name:
            Tenant identifier.

        Returns
        -------
        str
            Version string such as ``"v1"`` (first submission) or ``"v4"``.
        """
        versions = self.list_versions(tenant_name)
        if not versions:
            return "v1"
        max_num = max(int(v["RowKey"].lstrip("v")) for v in versions)
        return f"v{max_num + 1}"

    def _upsert_registry(self, tenant_name: str, version: str) -> None:
        """Write or update the TenantRegistry pointer for a tenant.

        Parameters
        ----------
        tenant_name:
            Tenant identifier (``PartitionKey``).
        version:
            The version key to set as current (e.g. ``"v2"``).
        """
        now = datetime.now(UTC).isoformat()
        entity = {
            "PartitionKey": tenant_name,
            "RowKey": "current",
            "CurrentVersion": version,
            "Status": "active",
            "CreatedAt": now,
        }
        table = self._registry_table()
        if table:
            table.upsert_entity(entity)
        else:
            self._memory[REGISTRY_TABLE][tenant_name] = entity

    def _get_registry(self, tenant_name: str) -> dict | None:
        """Fetch the TenantRegistry entry for a tenant.

        Parameters
        ----------
        tenant_name:
            Tenant identifier.

        Returns
        -------
        dict | None
            Registry entity dict with a ``CurrentVersion`` key, or ``None``.
        """
        table = self._registry_table()
        if table:
            try:
                return dict(table.get_entity(tenant_name, "current"))
            except Exception:
                return None
        return self._memory[REGISTRY_TABLE].get(tenant_name)

    @staticmethod
    def _deserialize(entity: dict) -> dict:
        """Deserialise a raw Table Storage entity dict.

        JSON-encoded fields (``FormData``, ``GeneratedTfvars``) are decoded
        back to Python dicts/lists.  All other fields are returned as-is.

        Parameters
        ----------
        entity:
            Raw entity dict from the Azure SDK or the in-memory fallback.

        Returns
        -------
        dict
            Entity dict with JSON string fields replaced by parsed objects.
        """
        result = dict(entity)
        for field in ("FormData", "GeneratedTfvars"):
            if field in result and isinstance(result[field], str):
                try:
                    result[field] = json.loads(result[field])
                except (json.JSONDecodeError, TypeError):
                    pass
        return result
