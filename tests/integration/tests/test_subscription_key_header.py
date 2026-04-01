from __future__ import annotations

import pytest

pytestmark = [
    pytest.mark.live,
    pytest.mark.skip(reason="APIM uses custom subscription header api-key; Ocp-Apim-Subscription-Key is unsupported"),
]


def test_legacy_subscription_header_support_is_disabled() -> None:
    """Document that this legacy-header regression test must remain skipped."""
    raise AssertionError("This test should always be skipped")
