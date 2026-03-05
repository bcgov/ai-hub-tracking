"""Azure Table Storage client – CRUD + versioning for tenant requests."""

from __future__ import annotations

import json
from datetime import UTC, datetime
from typing import Any

from azure.data.tables import TableClient, TableServiceClient

from src.config import settings

REQUESTS_TABLE = "TenantRequests"
REGISTRY_TABLE = "TenantRegistry"


class TenantStore:
    """Thin wrapper around Azure Table Storage for tenant request persistence."""

    def __init__(self) -> None:
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
        if self._service:
            self._service.create_table_if_not_exists(REQUESTS_TABLE)
            self._service.create_table_if_not_exists(REGISTRY_TABLE)

    def _requests_table(self) -> TableClient | None:
        if self._service:
            self._ensure_tables()
            return self._service.get_table_client(REQUESTS_TABLE)
        return None

    def _registry_table(self) -> TableClient | None:
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
        reg = self._get_registry(tenant_name)
        if not reg:
            return None
        return self.get_version(tenant_name, reg["CurrentVersion"])

    def get_version(self, tenant_name: str, version: str) -> dict | None:
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
        table = self._requests_table()
        if table:
            entities = table.query_entities(f"Status eq '{status}'")
            return [self._deserialize(e) for e in entities]
        else:
            return [
                self._deserialize(v) for v in self._memory[REQUESTS_TABLE].values() if v.get("Status") == status
            ]

    def list_all_current(self) -> list[dict]:
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
        versions = self.list_versions(tenant_name)
        if not versions:
            return "v1"
        max_num = max(int(v["RowKey"].lstrip("v")) for v in versions)
        return f"v{max_num + 1}"

    def _upsert_registry(self, tenant_name: str, version: str) -> None:
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
        table = self._registry_table()
        if table:
            try:
                return dict(table.get_entity(tenant_name, "current"))
            except Exception:
                return None
        return self._memory[REGISTRY_TABLE].get(tenant_name)

    @staticmethod
    def _deserialize(entity: dict) -> dict:
        result = dict(entity)
        for field in ("FormData", "GeneratedTfvars"):
            if field in result and isinstance(result[field], str):
                try:
                    result[field] = json.loads(result[field])
                except (json.JSONDecodeError, TypeError):
                    pass
        return result
