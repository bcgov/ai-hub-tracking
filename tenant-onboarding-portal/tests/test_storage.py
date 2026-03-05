"""Tests for the Table Storage layer (uses in-memory fallback)."""

from __future__ import annotations

from src.storage.table_storage import TenantStore


def test_create_and_retrieve():
    store = TenantStore()
    version = store.create_request(
        tenant_name="test-tenant",
        display_name="Test Tenant",
        form_data={"ministry": "CITZ", "project_name": "test-tenant"},
        generated_tfvars={"dev": "...", "test": "...", "prod": "..."},
        submitted_by="user@gov.bc.ca",
    )
    assert version == "v1"

    current = store.get_current("test-tenant")
    assert current is not None
    assert current["DisplayName"] == "Test Tenant"
    assert current["Status"] == "submitted"


def test_versioning():
    store = TenantStore()
    v1 = store.create_request("proj", "Project", {}, {}, "a@gov.bc.ca")
    v2 = store.create_request("proj", "Project Updated", {}, {}, "a@gov.bc.ca")
    assert v1 == "v1"
    assert v2 == "v2"

    current = store.get_current("proj")
    assert current["RowKey"] == "v2"
    assert current["DisplayName"] == "Project Updated"

    versions = store.list_versions("proj")
    assert len(versions) == 2


def test_status_update():
    store = TenantStore()
    store.create_request("proj2", "Project 2", {}, {}, "a@gov.bc.ca")
    store.update_status("proj2", "v1", "approved", reviewed_by="admin@gov.bc.ca", review_notes="Looks good")

    v = store.get_version("proj2", "v1")
    assert v["Status"] == "approved"
    assert v["ReviewedBy"] == "admin@gov.bc.ca"


def test_list_by_status():
    store = TenantStore()
    store.create_request("a", "A", {}, {}, "x@gov.bc.ca")
    store.create_request("b", "B", {}, {}, "x@gov.bc.ca")
    store.update_status("a", "v1", "approved")

    submitted = store.list_by_status("submitted")
    assert len(submitted) == 1
    assert submitted[0]["PartitionKey"] == "b"


def test_list_by_user():
    store = TenantStore()
    store.create_request("p1", "P1", {}, {}, "alice@gov.bc.ca")
    store.create_request("p2", "P2", {}, {}, "bob@gov.bc.ca")

    alice = store.list_by_user("alice@gov.bc.ca")
    assert len(alice) == 1
    assert alice[0]["PartitionKey"] == "p1"
