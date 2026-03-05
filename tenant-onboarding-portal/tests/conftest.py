"""Shared test fixtures."""

from __future__ import annotations

import os

import pytest
from fastapi.testclient import TestClient

# Ensure no Azure connections in tests
os.environ["PORTAL_TABLE_STORAGE_CONNECTION_STRING"] = ""
os.environ["PORTAL_TABLE_STORAGE_ACCOUNT_URL"] = ""
os.environ["PORTAL_SECRET_KEY"] = "test-secret-key"
os.environ["PORTAL_OIDC_DISCOVERY_URL"] = ""


@pytest.fixture
def client():
    from src.main import app

    with TestClient(app) as c:
        yield c


@pytest.fixture
def authed_client(client):
    """A test client with a simulated logged-in user session."""
    # Use the dev auto-login route
    client.get("/auth/login", follow_redirects=False)
    return client
