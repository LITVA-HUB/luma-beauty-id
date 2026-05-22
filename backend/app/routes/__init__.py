from __future__ import annotations

from . import advisor, auth, beauty_id, cart, catalog, checkout, events, feedback, privacy, profile, recommendations, routines, scan, selection, system

ROUTERS = (
    system.router,
    auth.router,
    profile.router,
    beauty_id.router,
    catalog.router,
    recommendations.router,
    routines.router,
    selection.router,
    scan.router,
    advisor.router,
    cart.router,
    checkout.router,
    feedback.router,
    events.router,
    privacy.router,
)
