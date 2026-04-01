from __future__ import annotations

import os
from pathlib import Path

import pytest

from ai_hub_integration import ApimClient, IntegrationConfig


@pytest.fixture(scope="session")
def integration_config() -> IntegrationConfig:
    return IntegrationConfig.load(os.getenv("TEST_ENV"))


@pytest.fixture(scope="session")
def client(integration_config: IntegrationConfig) -> ApimClient:
    return ApimClient(integration_config)


@pytest.fixture(scope="session")
def test_form_jpg(integration_config: IntegrationConfig) -> Path:
    return integration_config.tests_dir / "test_form.jpg"


@pytest.fixture(scope="session")
def test_form_small_jpg(integration_config: IntegrationConfig) -> Path:
    return integration_config.tests_dir / "test_form_small.jpg"
