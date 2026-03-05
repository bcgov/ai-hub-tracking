"""Tests for the tfvars generator."""

from __future__ import annotations

from src.models.tenant import TenantFormData
from src.services.tfvars_generator import generate_all_env_tfvars


def _sample_form() -> TenantFormData:
    return TenantFormData(
        project_name="test-project",
        display_name="Test Project",
        ministry="CITZ",
        department="Corporate Online Services",
        openai_enabled=True,
        ai_search_enabled=True,
        document_intelligence_enabled=False,
        speech_services_enabled=False,
        cosmos_db_enabled=False,
        storage_account_enabled=True,
        key_vault_enabled=False,
        model_families=["gpt-4.1", "embeddings"],
        capacity_tier="standard",
        apim_auth_mode="subscription_key",
        rate_limiting_enabled=True,
        tokens_per_minute=1000,
        pii_redaction_enabled=True,
        usage_logging_enabled=True,
        admin_emails=["alice@gov.bc.ca", "bob@gov.bc.ca"],
    )


def test_generates_all_three_envs():
    result = generate_all_env_tfvars(_sample_form())
    assert set(result.keys()) == {"dev", "test", "prod"}


def test_tenant_name_in_output():
    result = generate_all_env_tfvars(_sample_form())
    for env in ("dev", "test", "prod"):
        assert 'tenant_name  = "test-project"' in result[env]


def test_env_tag_matches():
    result = generate_all_env_tfvars(_sample_form())
    assert 'environment = "dev"' in result["dev"]
    assert 'environment = "test"' in result["test"]
    assert 'environment = "prod"' in result["prod"]


def test_speech_services_always_present():
    """Speech services block must be present even when disabled (map(any) constraint)."""
    result = generate_all_env_tfvars(_sample_form())
    for env in ("dev", "test", "prod"):
        assert "speech_services" in result[env]
        assert "enabled = false" in result[env]


def test_model_deployments_match_families():
    result = generate_all_env_tfvars(_sample_form())
    # gpt-4.1 family has 3 models, embeddings has 3 = 6 total
    for env in ("dev", "test", "prod"):
        assert result[env].count("model_name") == 6


def test_admin_emails_in_output():
    result = generate_all_env_tfvars(_sample_form())
    for env in ("dev", "test", "prod"):
        assert "alice@gov.bc.ca" in result[env]
        assert "bob@gov.bc.ca" in result[env]


def test_reduced_capacity_tier():
    form = _sample_form()
    form.capacity_tier = "reduced"
    result = generate_all_env_tfvars(form)
    # GPT-4.1 default capacity is 300, reduced = 0.5x = 150
    assert "capacity      = 150" in result["dev"]


def test_retention_differs_by_env():
    result = generate_all_env_tfvars(_sample_form())
    assert "retention_days = 30" in result["dev"]
    assert "retention_days = 30" in result["test"]
    assert "retention_days = 90" in result["prod"]


def test_soft_delete_differs_by_env():
    form = _sample_form()
    form.key_vault_enabled = True
    result = generate_all_env_tfvars(form)
    assert "soft_delete_retention_days = 7" in result["dev"]
    assert "soft_delete_retention_days = 30" in result["test"]
    assert "soft_delete_retention_days = 90" in result["prod"]
