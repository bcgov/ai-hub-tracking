"""Form schema definition – versioned field metadata for the tenant onboarding form."""

from __future__ import annotations

FORM_VERSION = "2026.03.1"

# BC Gov ministries dropdown
MINISTRIES = [
    "AF", "AG", "CITZ", "ECC", "EMCR", "ENV", "FIN",
    "FOR", "GCPE", "HLTH", "IRR", "JEDI", "LBR", "MCF",
    "MMHA", "MOTI", "MUNI", "NR", "PSFS", "PSSG",
    "SDPR", "TACS", "WLRS",
]

# Model family groupings
MODEL_FAMILIES = {
    "gpt-4.1": {
        "label": "GPT-4.1 Series",
        "models": [
            {"name": "gpt-4.1", "model_name": "gpt-4.1", "model_version": "2025-04-14", "scale_type": "GlobalStandard", "default_capacity": 300},
            {"name": "gpt-4.1-mini", "model_name": "gpt-4.1-mini", "model_version": "2025-04-14", "scale_type": "GlobalStandard", "default_capacity": 1500},
            {"name": "gpt-4.1-nano", "model_name": "gpt-4.1-nano", "model_version": "2025-04-14", "scale_type": "GlobalStandard", "default_capacity": 1500},
        ],
    },
    "gpt-4o": {
        "label": "GPT-4o Series",
        "models": [
            {"name": "gpt-4o", "model_name": "gpt-4o", "model_version": "2024-11-20", "scale_type": "GlobalStandard", "default_capacity": 300},
            {"name": "gpt-4o-mini", "model_name": "gpt-4o-mini", "model_version": "2024-07-18", "scale_type": "GlobalStandard", "default_capacity": 1500},
        ],
    },
    "gpt-5": {
        "label": "GPT-5 Series",
        "models": [
            {"name": "gpt-5-mini", "model_name": "gpt-5-mini", "model_version": "2025-08-07", "scale_type": "GlobalStandard", "default_capacity": 100},
            {"name": "gpt-5-nano", "model_name": "gpt-5-nano", "model_version": "2025-08-07", "scale_type": "GlobalStandard", "default_capacity": 1500},
        ],
    },
    "gpt-5.1": {
        "label": "GPT-5.1 Series",
        "models": [
            {"name": "gpt-5.1-chat", "model_name": "gpt-5.1-chat", "model_version": "2025-11-13", "scale_type": "GlobalStandard", "default_capacity": 50},
            {"name": "gpt-5.1-codex-mini", "model_name": "gpt-5.1-codex-mini", "model_version": "2025-11-13", "scale_type": "GlobalStandard", "default_capacity": 100},
        ],
    },
    "reasoning": {
        "label": "Reasoning Models",
        "models": [
            {"name": "o1", "model_name": "o1", "model_version": "2024-12-17", "scale_type": "GlobalStandard", "default_capacity": 50},
            {"name": "o3-mini", "model_name": "o3-mini", "model_version": "2025-01-31", "scale_type": "GlobalStandard", "default_capacity": 50},
            {"name": "o4-mini", "model_name": "o4-mini", "model_version": "2025-04-16", "scale_type": "GlobalStandard", "default_capacity": 100},
        ],
    },
    "embeddings": {
        "label": "Embedding Models",
        "models": [
            {"name": "text-embedding-ada-002", "model_name": "text-embedding-ada-002", "model_version": "2", "scale_type": "GlobalStandard", "default_capacity": 100},
            {"name": "text-embedding-3-large", "model_name": "text-embedding-3-large", "model_version": "1", "scale_type": "GlobalStandard", "default_capacity": 100},
            {"name": "text-embedding-3-small", "model_name": "text-embedding-3-small", "model_version": "1", "scale_type": "GlobalStandard", "default_capacity": 100},
        ],
    },
}

# Capacity tier multipliers (relative to default_capacity)
CAPACITY_TIERS = {
    "reduced": {"label": "Reduced (0.5× quota)", "multiplier": 0.5},
    "standard": {"label": "Standard (1% quota)", "multiplier": 1.0},
    "elevated": {"label": "Elevated (2× quota)", "multiplier": 2.0},
}

# Complete form schema for template rendering
FORM_SCHEMA = {
    "version": FORM_VERSION,
    "ministries": MINISTRIES,
    "model_families": MODEL_FAMILIES,
    "capacity_tiers": CAPACITY_TIERS,
    "auth_modes": [
        {"value": "subscription_key", "label": "API Key (Subscription Key)"},
        {"value": "oauth2", "label": "OAuth2 (Azure AD JWT)"},
    ],
}
