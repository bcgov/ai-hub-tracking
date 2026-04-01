from __future__ import annotations

import os
from pathlib import Path

import pytest

from ai_hub_integration import ApimClient, IntegrationConfig


@pytest.fixture(scope="session")
def integration_config() -> IntegrationConfig:
    """Load a shared integration configuration once for the entire test session."""
    return IntegrationConfig.load(os.getenv("TEST_ENV"))


@pytest.fixture(scope="session")
def client(integration_config: IntegrationConfig) -> ApimClient:
    """Create the shared APIM client used by live integration tests."""
    return ApimClient(integration_config)


@pytest.fixture(scope="session")
def test_form_jpg(integration_config: IntegrationConfig) -> Path:
    """Return the primary JPG document fixture used in OCR-related tests."""
    return integration_config.tests_dir / "test_form.jpg"


@pytest.fixture(scope="session")
def test_form_small_jpg(integration_config: IntegrationConfig) -> Path:
    """Return the smaller JPG fixture used in binary upload coverage."""
    return integration_config.tests_dir / "test_form_small.jpg"
