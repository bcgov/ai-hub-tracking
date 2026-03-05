"""Tests for the Pydantic tenant model."""

from __future__ import annotations

import pytest

from src.models.tenant import TenantFormData


def test_valid_tenant_form():
    data = TenantFormData(
        project_name="my-test-project",
        display_name="My Test Project",
        ministry="CITZ",
        admin_emails=["test.user@gov.bc.ca"],
    )
    assert data.project_name == "my-test-project"
    assert data.openai_enabled is True
    assert data.model_families == ["gpt-4.1", "gpt-4o", "embeddings"]


def test_invalid_project_name():
    with pytest.raises(ValueError, match="Project name must be lowercase"):
        TenantFormData(project_name="AB", display_name="X", ministry="CITZ")


def test_invalid_project_name_uppercase():
    with pytest.raises(ValueError, match="Project name must be lowercase"):
        TenantFormData(project_name="MyProject", display_name="X", ministry="CITZ")


def test_invalid_email_domain():
    with pytest.raises(ValueError, match="@gov.bc.ca"):
        TenantFormData(
            project_name="valid-name",
            display_name="Valid",
            ministry="CITZ",
            admin_emails=["user@gmail.com"],
        )


def test_from_form_checkbox_parsing():
    form_data = {
        "project_name": "test-project",
        "display_name": "Test Project",
        "ministry": "WLRS",
        "openai_enabled": "on",
        "ai_search_enabled": "",
        "storage_account_enabled": "on",
        "model_families": "gpt-4.1,embeddings",
        "capacity_tier": "standard",
        "admin_emails": "a@gov.bc.ca, b@gov.bc.ca",
        "tokens_per_minute": "2000",
    }
    result = TenantFormData.from_form(form_data)
    assert result.openai_enabled is True
    assert result.ai_search_enabled is False
    assert result.model_families == ["gpt-4.1", "embeddings"]
    assert result.admin_emails == ["a@gov.bc.ca", "b@gov.bc.ca"]
    assert result.tokens_per_minute == 2000
