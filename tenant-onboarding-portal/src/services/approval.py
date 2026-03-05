"""Admin approval service – status transitions and validation."""

from __future__ import annotations

VALID_TRANSITIONS = {
    "draft": ["submitted"],
    "submitted": ["approved", "rejected"],
    "approved": [],
    "rejected": ["submitted"],
}


def can_transition(current_status: str, target_status: str) -> bool:
    """Check whether a status transition is allowed."""
    return target_status in VALID_TRANSITIONS.get(current_status, [])
