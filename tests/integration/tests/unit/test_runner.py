from __future__ import annotations

from ai_hub_integration.runner import build_marker_expression, normalize_selector


def test_build_marker_expression_for_direct_group() -> None:
    """Verify that the direct group excludes proxy and AI-eval suites by default."""
    expression = build_marker_expression("direct", include_ai_eval=False)

    assert expression == "live and not requires_proxy and not ai_eval"


def test_normalize_selector_maps_legacy_bats_name() -> None:
    """Verify that a legacy BATS suite alias maps to the pytest file path."""
    assert normalize_selector("apim-key-rotation.bats") == "tests/test_apim_key_rotation.py"
