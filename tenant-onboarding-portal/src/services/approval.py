"""Admin approval service – status transitions and validation.

Defines the allowed state machine for tenant request statuses and exposes
a helper function used by admin routes before committing status changes.

State machine
-------------
::

    draft ──► submitted ──► approved
                  │
                  ▼
              rejected ──► submitted   (re-submit after changes)

A request starts as ``submitted`` when created from the portal form.
Admins can approve or reject it.  A rejected request can be re-submitted
after the tenant updates their configuration.
"""

from __future__ import annotations

VALID_TRANSITIONS: dict[str, list[str]] = {
    "draft": ["submitted"],
    "submitted": ["approved", "rejected"],
    "approved": [],
    "rejected": ["submitted"],
}
"""Adjacency map of allowed status transitions.

Keys are the *current* status; values are the statuses the request
may legally move to.  An empty list means the status is terminal.
"""


def can_transition(current_status: str, target_status: str) -> bool:
    """Check whether a status transition is permitted by the state machine.

    Parameters
    ----------
    current_status:
        The request's existing status (e.g. ``"submitted"``).
    target_status:
        The desired new status (e.g. ``"approved"``).

    Returns
    -------
    bool
        ``True`` if the transition is in :data:`VALID_TRANSITIONS`,
        ``False`` otherwise.

    Examples
    --------
    >>> can_transition("submitted", "approved")
    True
    >>> can_transition("approved", "rejected")
    False
    """
    return target_status in VALID_TRANSITIONS.get(current_status, [])
