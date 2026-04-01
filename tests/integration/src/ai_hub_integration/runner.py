from __future__ import annotations

from pathlib import Path

SUITE_ALIASES = {
    "chat-completions.bats": "tests/test_chat_completions.py",
    "chat-completions": "tests/test_chat_completions.py",
    "test_chat_completions.py": "tests/test_chat_completions.py",
    "document-intelligence.bats": "tests/test_document_intelligence.py",
    "document-intelligence": "tests/test_document_intelligence.py",
    "test_document_intelligence.py": "tests/test_document_intelligence.py",
    "document-intelligence-binary.bats": "tests/test_document_intelligence_binary.py",
    "document-intelligence-binary": "tests/test_document_intelligence_binary.py",
    "test_document_intelligence_binary.py": "tests/test_document_intelligence_binary.py",
    "app-gateway.bats": "tests/test_app_gateway.py",
    "app-gateway": "tests/test_app_gateway.py",
    "test_app_gateway.py": "tests/test_app_gateway.py",
    "v1-chat-completions.bats": "tests/test_v1_chat_completions.py",
    "v1-chat-completions": "tests/test_v1_chat_completions.py",
    "test_v1_chat_completions.py": "tests/test_v1_chat_completions.py",
    "tenant-info.bats": "tests/test_tenant_info.py",
    "tenant-info": "tests/test_tenant_info.py",
    "test_tenant_info.py": "tests/test_tenant_info.py",
    "apim-key-rotation.bats": "tests/test_apim_key_rotation.py",
    "apim-key-rotation": "tests/test_apim_key_rotation.py",
    "test_apim_key_rotation.py": "tests/test_apim_key_rotation.py",
    "mistral.bats": "tests/test_mistral.py",
    "mistral": "tests/test_mistral.py",
    "test_mistral.py": "tests/test_mistral.py",
    "ai-evaluation": "tests/test_ai_evaluation.py",
    "test_ai_evaluation.py": "tests/test_ai_evaluation.py",
    "subscription-key-header.bats": "tests/test_subscription_key_header.py",
    "subscription-key-header": "tests/test_subscription_key_header.py",
    "test_subscription_key_header.py": "tests/test_subscription_key_header.py",
}


def build_marker_expression(group: str, include_ai_eval: bool) -> str:
    """Build the pytest marker expression for the selected execution group."""
    if group not in {"all", "direct", "proxy"}:
        raise ValueError(f"Unsupported test group: {group}")

    parts = ["live"]
    if group == "direct":
        parts.append("not requires_proxy")
    elif group == "proxy":
        parts.append("requires_proxy")

    if not include_ai_eval:
        parts.append("not ai_eval")

    return " and ".join(parts)


def normalize_selector(selector: str) -> str:
    """Normalize suite aliases and filesystem paths into pytest selectors."""
    normalized = selector.replace("\\", "/")
    if normalized in SUITE_ALIASES:
        return SUITE_ALIASES[normalized]

    path = Path(normalized)
    if path.exists():
        return normalized

    return normalized


__all__ = ["SUITE_ALIASES", "build_marker_expression", "normalize_selector"]
