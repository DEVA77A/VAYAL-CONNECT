"""Explicit straight-line estimates. No road-distance or exact-arrival claims."""
from datetime import datetime, timezone, timedelta, date
from math import radians, sin, cos, atan2, sqrt, ceil
from app.schemas.location import Coordinates


def distance_km(origin, destination):
    a = Coordinates.model_validate(origin)
    b = Coordinates.model_validate(destination)
    lat1, lat2 = radians(a.latitude), radians(b.latitude)
    dlat, dlon = lat2 - lat1, radians(b.longitude - a.longitude)
    h = sin(dlat / 2)**2 + cos(lat1) * cos(lat2) * sin(dlon / 2)**2
    return 6371.0088 * 2 * atan2(sqrt(h), sqrt(max(0, 1-h)))


def estimate_delivery(origin, destination, harvest_date=None, method="DELIVERY"):
    from app.core.config import settings
    if method == "PICKUP":
        return {"available": False, "method": "PICKUP", "message": "Collect from the farmer's pickup address."}
    if not origin or not destination:
        return {"available": False, "method": "DELIVERY", "message": "Verified destination and farm coordinates are required for an estimate."}
    km = round(distance_km(origin, destination), 2)
    now = datetime.now(timezone.utc)
    ready = now
    if harvest_date:
        harvest = date.fromisoformat(str(harvest_date)[:10])
        ready = max(now, datetime.combine(harvest, datetime.min.time(), tzinfo=timezone.utc))
    travel_hours = ceil(km * settings.DELIVERY_DISTANCE_FACTOR / settings.DELIVERY_SPEED_KMH)
    earliest = ready + timedelta(hours=settings.DELIVERY_PREPARATION_HOURS + travel_hours)
    return {"available": True, "method": "DELIVERY", "distance_km": km, "distance_type": "STRAIGHT_LINE",
        "origin": origin, "destination": destination, "estimated_at": now.isoformat(),
        "arrival_from": earliest.isoformat(), "arrival_to": (earliest + timedelta(hours=24)).isoformat(),
        "speed_kmh": settings.DELIVERY_SPEED_KMH, "distance_factor": settings.DELIVERY_DISTANCE_FACTOR,
        "preparation_hours": settings.DELIVERY_PREPARATION_HOURS,
        "assumptions": "Straight-line distance; travel estimate applies a distance factor, preparation time and a 24-hour uncertainty window. Farmer confirmation required."}
