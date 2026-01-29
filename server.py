"""
Flask server exposing the NES Outage proximity API.

Endpoints:
    GET /nearest?address=<address>&limit=<n>
    GET /events - list all current outage events
    GET /health - health check
"""

from flask import Flask, request, jsonify
from nes_service import (
    find_nearest_by_address,
    fetch_nes_events,
    geocode_address,
)

app = Flask(__name__)


@app.route("/health")
def health():
    return jsonify({"status": "ok"})


@app.route("/events")
def events():
    """Return all current NES outage events."""
    events = fetch_nes_events()
    return jsonify({
        "count": len(events),
        "events": [e.to_dict() for e in events],
    })


@app.route("/nearest")
def nearest():
    """
    Find nearest outage events to an address.

    Query params:
        address (required): Street address to geocode
        limit (optional): Max events to return (default 5)
    """
    address = request.args.get("address")
    if not address:
        return jsonify({"error": "Missing required 'address' parameter"}), 400

    try:
        limit = int(request.args.get("limit", 5))
    except ValueError:
        return jsonify({"error": "Invalid 'limit' parameter"}), 400

    result = find_nearest_by_address(address, limit=limit)

    if "error" in result:
        return jsonify(result), 404

    return jsonify(result)


@app.route("/geocode")
def geocode():
    """
    Geocode an address (utility endpoint for testing).

    Query params:
        address (required): Street address to geocode
    """
    address = request.args.get("address")
    if not address:
        return jsonify({"error": "Missing required 'address' parameter"}), 400

    coords = geocode_address(address)
    if coords is None:
        return jsonify({"error": "Could not geocode address"}), 404

    return jsonify({
        "address": address,
        "coordinates": {"lat": coords.lat, "lng": coords.lng},
    })


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="NES Outage API Server")
    parser.add_argument("--host", default="127.0.0.1", help="Host to bind to")
    parser.add_argument("--port", "-p", type=int, default=5000, help="Port to bind to")
    parser.add_argument("--debug", action="store_true", help="Enable debug mode")
    args = parser.parse_args()

    print(f"Starting NES Outage API on http://{args.host}:{args.port}")
    print("Endpoints:")
    print(f"  GET /nearest?address=<address>&limit=<n>")
    print(f"  GET /events")
    print(f"  GET /geocode?address=<address>")
    print(f"  GET /health")

    app.run(host=args.host, port=args.port, debug=args.debug)
