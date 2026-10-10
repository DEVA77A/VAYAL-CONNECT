"""
VayalConnect Backend — Date Utilities
"""

from datetime import datetime, timezone, date
from typing import Optional


def utc_now() -> datetime:
    """Get current UTC datetime."""
    return datetime.now(timezone.utc)


def date_today() -> date:
    """Get today's date in UTC."""
    return datetime.now(timezone.utc).date()


def is_within_days(dt: datetime, days: int) -> bool:
    """Check if a datetime is within N days from now."""
    delta = utc_now() - dt
    return delta.days <= days


def format_date(dt: Optional[datetime]) -> Optional[str]:
    """Format datetime for API response."""
    if dt is None:
        return None
    return dt.isoformat()
