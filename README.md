# NES Outage Checker

Query Nashville Electric Service (NES) power outage information by address, database ID, or reference number.

## Quick Start

```bash
# Start the API server
docker compose up -d

# Find the nearest outage to an address
./nes-outage.sh -a "123 Main St, Nashville, TN"

# Stop the API server
docker compose down
```

## Requirements

- Docker and Docker Compose
- bash, curl, jq (for the CLI script)

## Usage

### Command Line

```bash
# Find nearest outage to an address
./nes-outage.sh -a "123 Main St, Nashville, TN"

# Find 5 nearest outages
./nes-outage.sh -a "123 Main St, Nashville, TN" -n 5

# Query by database ID
./nes-outage.sh -i 1978957

# Query by public reference number
./nes-outage.sh -r 2621583
```

### API Endpoints

The service runs on `http://127.0.0.1:5000` by default.

| Endpoint | Description |
|----------|-------------|
| `GET /nearest?address=<address>&limit=<n>` | Find nearest outages to an address |
| `GET /events` | List all current outage events |
| `GET /geocode?address=<address>` | Geocode an address to coordinates |
| `GET /health` | Health check |

#### Example API Requests

```bash
# Find nearest outages
curl "http://127.0.0.1:5000/nearest?address=123+Main+St,+Nashville,+TN&limit=3"

# List all events
curl "http://127.0.0.1:5000/events"

# Geocode an address
curl "http://127.0.0.1:5000/geocode?address=123+Main+St,+Nashville,+TN"
```

## Architecture

```
nes-outage.sh          CLI interface (bash)
       |
       v
server.py              Flask API server
       |
       v
nes_service.py         Core logic (geocoding, NES API, distance calculation)
       |
       v
External APIs:
  - US Census Geocoder (address -> coordinates)
  - NES/Utilisocial API (outage events)
```

## Files

| File | Description |
|------|-------------|
| `nes-outage.sh` | Bash CLI for querying outages |
| `nes_service.py` | Core Python module with geocoding and proximity logic |
| `server.py` | Flask web server exposing the API |
| `Dockerfile` | Container image definition |
| `docker-compose.yml` | Container orchestration |
| `requirements.txt` | Python dependencies |

## How It Works

1. **Geocoding**: Addresses are converted to lat/lng coordinates using the free US Census Geocoder API
2. **Event Fetching**: Current outage events are fetched from NES's public Utilisocial API
3. **Distance Calculation**: Haversine formula calculates great-circle distance between coordinates
4. **Sorting**: Events are sorted by distance and the nearest N are returned

## Output

The CLI displays outage details including:
- Status and cause
- Database ID and public reference number
- Number of affected homes
- Start time, last update, and duration
- Distance from your address (when using `-a`)
- Google Maps link showing both your location and the outage (when using `-a`)
