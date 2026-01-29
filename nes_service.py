"""
NES Outage Service - Core logic for geocoding and proximity search.

This module can be imported directly or exposed via the Flask server.
"""

import math
import requests
from typing import Optional
from dataclasses import dataclass


NES_API_URL = "https://utilisocial.io/datacapable/v2/p/NES/map/events"
CENSUS_GEOCODER_URL = "https://geocoding.geo.census.gov/geocoder/locations/onelineaddress"


@dataclass
class Coordinates:
    lat: float
    lng: float


@dataclass
class OutageEvent:
    id: int
    identifier: str
    title: str
    status: str
    cause: Optional[str]
    num_people: int
    start_time: int
    last_updated_time: int
    latitude: float
    longitude: float
    distance_miles: Optional[float] = None

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "identifier": self.identifier,
            "title": self.title,
            "status": self.status,
            "cause": self.cause,
            "num_people": self.num_people,
            "start_time": self.start_time,
            "last_updated_time": self.last_updated_time,
            "latitude": self.latitude,
            "longitude": self.longitude,
            "distance_miles": self.distance_miles,
        }


def geocode_address(address: str) -> Optional[Coordinates]:
    """
    Convert an address string to coordinates using the US Census Geocoder.
    Returns None if geocoding fails.
    """
    params = {
        "address": address,
        "benchmark": "Public_AR_Current",
        "format": "json",
    }

    try:
        resp = requests.get(CENSUS_GEOCODER_URL, params=params, timeout=10)
        resp.raise_for_status()
        data = resp.json()

        matches = data.get("result", {}).get("addressMatches", [])
        if not matches:
            return None

        coords = matches[0].get("coordinates", {})
        return Coordinates(
            lat=coords.get("y"),
            lng=coords.get("x"),
        )
    except (requests.RequestException, KeyError, IndexError):
        return None


def haversine_miles(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """
    Calculate the great-circle distance between two points in miles.
    """
    R = 3959  # Earth's radius in miles

    lat1_rad = math.radians(lat1)
    lat2_rad = math.radians(lat2)
    delta_lat = math.radians(lat2 - lat1)
    delta_lng = math.radians(lng2 - lng1)

    a = (math.sin(delta_lat / 2) ** 2 +
         math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(delta_lng / 2) ** 2)
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

    return R * c


def fetch_nes_events() -> list[OutageEvent]:
    """
    Fetch all current outage events from the NES API.
    """
    try:
        resp = requests.get(NES_API_URL, timeout=10)
        resp.raise_for_status()
        data = resp.json()

        events = []
        for item in data:
            events.append(OutageEvent(
                id=item.get("id"),
                identifier=item.get("identifier"),
                title=item.get("title", ""),
                status=item.get("status", ""),
                cause=item.get("cause"),
                num_people=item.get("numPeople", 0),
                start_time=item.get("startTime", 0),
                last_updated_time=item.get("lastUpdatedTime", 0),
                latitude=item.get("latitude", 0),
                longitude=item.get("longitude", 0),
            ))
        return events
    except requests.RequestException:
        return []


def find_nearest_events(
    coords: Coordinates,
    limit: int = 5,
    events: Optional[list[OutageEvent]] = None,
) -> list[OutageEvent]:
    """
    Find the nearest outage events to the given coordinates.

    Args:
        coords: The reference coordinates to measure distance from
        limit: Maximum number of events to return
        events: Optional pre-fetched events list; fetches from API if not provided

    Returns:
        List of OutageEvent objects sorted by distance, with distance_miles populated
    """
    if events is None:
        events = fetch_nes_events()

    for event in events:
        event.distance_miles = haversine_miles(
            coords.lat, coords.lng,
            event.latitude, event.longitude
        )

    sorted_events = sorted(events, key=lambda e: e.distance_miles or float('inf'))
    return sorted_events[:limit]


def find_nearest_by_address(address: str, limit: int = 5) -> dict:
    """
    High-level function: geocode an address and find nearest outage events.

    Returns a dict suitable for JSON serialization.
    """
    coords = geocode_address(address)
    if coords is None:
        return {
            "error": "Could not geocode address",
            "query_address": address,
        }

    events = find_nearest_events(coords, limit=limit)

    return {
        "query_address": address,
        "coordinates": {"lat": coords.lat, "lng": coords.lng},
        "events": [e.to_dict() for e in events],
    }


# CLI interface for testing
if __name__ == "__main__":
    import sys
    import json

    if len(sys.argv) < 2:
        print("Usage: python nes_service.py <address>")
        print("Example: python nes_service.py '123 Main St, Nashville, TN'")
        sys.exit(1)

    address = " ".join(sys.argv[1:])
    result = find_nearest_by_address(address, limit=5)
    print(json.dumps(result, indent=2))
