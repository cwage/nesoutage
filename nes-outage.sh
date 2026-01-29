#!/bin/bash

# NES Outage Checker
# Query local NES outage API by address, database ID, or reference number

API_BASE="http://127.0.0.1:5000"

usage() {
    echo "Usage: $0 [-a <address>] [-i <db_id>] [-r <reference_number>] [-n <limit>]"
    echo ""
    echo "Options:"
    echo "  -a <addr>  Find nearest outages to address"
    echo "  -i <id>    Query by database ID (e.g., 1978957)"
    echo "  -r <ref>   Query by public reference/identifier (e.g., 2621583)"
    echo "  -n <num>   Limit results when using -a (default: 1)"
    echo ""
    echo "Examples:"
    echo "  $0 -a '123 Main St, Nashville, TN'"
    echo "  $0 -a '123 Main St, Nashville, TN' -n 5"
    echo "  $0 -i 1978957"
    echo "  $0 -r 2621583"
    exit 1
}

format_timestamp() {
    local ts_ms="$1"
    local ts_sec=$((ts_ms / 1000))
    TZ="America/Chicago" date -d "@$ts_sec" "+%Y-%m-%d %I:%M:%S %p %Z"
}

print_outage() {
    local result="$1"
    local distance="$2"
    local home_lat="$3"
    local home_lng="$4"

    # Extract fields (API returns snake_case)
    id=$(echo "$result" | jq -r '.id')
    identifier=$(echo "$result" | jq -r '.identifier')
    title=$(echo "$result" | jq -r '.title')
    status=$(echo "$result" | jq -r '.status')
    num_people=$(echo "$result" | jq -r '.num_people')
    cause=$(echo "$result" | jq -r '.cause // "Not specified"')
    start_time=$(echo "$result" | jq -r '.start_time')
    last_updated=$(echo "$result" | jq -r '.last_updated_time')
    latitude=$(echo "$result" | jq -r '.latitude')
    longitude=$(echo "$result" | jq -r '.longitude')

    # Format timestamps
    start_formatted=$(format_timestamp "$start_time")
    updated_formatted=$(format_timestamp "$last_updated")

    # Calculate duration
    now_ms=$(($(date +%s) * 1000))
    duration_ms=$((now_ms - start_time))
    duration_hours=$((duration_ms / 1000 / 60 / 60))
    duration_days=$((duration_hours / 24))
    remaining_hours=$((duration_hours % 24))

    if [[ $duration_days -gt 0 ]]; then
        duration_str="${duration_days}d ${remaining_hours}h"
    else
        duration_str="${duration_hours}h"
    fi

    # Output
    echo "═══════════════════════════════════════════════════════"
    echo "  NES OUTAGE STATUS"
    echo "═══════════════════════════════════════════════════════"
    echo ""
    echo "  Title:            $title"
    echo "  Status:           $status"
    echo "  Cause:            ${cause:-Not specified}"
    echo ""
    echo "  Database ID:      $id"
    echo "  Reference #:      $identifier"
    echo ""
    echo "  Affected Homes:   $num_people"
    echo ""
    echo "  Start Time:       $start_formatted"
    echo "  Last Updated:     $updated_formatted"
    echo "  Duration:         $duration_str"
    echo ""
    if [[ -n "$distance" && "$distance" != "null" ]]; then
        printf "  Distance:         %.2f miles\n" "$distance"
    fi
    echo "  Location:         $latitude, $longitude"
    if [[ -n "$home_lat" && -n "$home_lng" ]]; then
        echo "  Map:              https://www.google.com/maps/dir/$home_lat,$home_lng/$latitude,$longitude"
    else
        echo "  Map:              https://www.google.com/maps?q=$latitude,$longitude"
    fi
    echo ""
    echo "═══════════════════════════════════════════════════════"
}

query_type=""
query_value=""
address=""
limit=1

while getopts "a:i:r:n:h" opt; do
    case $opt in
        a)
            query_type="address"
            address="$OPTARG"
            ;;
        i)
            query_type="id"
            query_value="$OPTARG"
            ;;
        r)
            query_type="identifier"
            query_value="$OPTARG"
            ;;
        n)
            limit="$OPTARG"
            ;;
        h)
            usage
            ;;
        *)
            usage
            ;;
    esac
done

if [[ -z "$query_type" ]]; then
    usage
fi

# Check if API is running
if ! curl -s "$API_BASE/health" > /dev/null 2>&1; then
    echo "Error: API not running. Start it with: docker compose up -d"
    exit 1
fi

if [[ "$query_type" == "address" ]]; then
    # Query by address using /nearest endpoint
    encoded_address=$(echo "$address" | jq -sRr @uri)
    response=$(curl -s "$API_BASE/nearest?address=$encoded_address&limit=$limit")

    if echo "$response" | jq -e '.error' > /dev/null 2>&1; then
        echo "Error: $(echo "$response" | jq -r '.error')"
        exit 1
    fi

    echo ""
    echo "  Address: $address"
    home_lat=$(echo "$response" | jq -r '.coordinates.lat')
    home_lng=$(echo "$response" | jq -r '.coordinates.lng')
    echo "  Coordinates: $home_lat, $home_lng"
    echo ""

    event_count=$(echo "$response" | jq '.events | length')
    if [[ "$event_count" -eq 0 ]]; then
        echo "No outages found near this address."
        exit 0
    fi

    for i in $(seq 0 $((event_count - 1))); do
        event=$(echo "$response" | jq ".events[$i]")
        distance=$(echo "$event" | jq -r '.distance_miles')
        print_outage "$event" "$distance" "$home_lat" "$home_lng"
        if [[ $i -lt $((event_count - 1)) ]]; then
            echo ""
        fi
    done
else
    # Query by ID or identifier using /events endpoint
    response=$(curl -s "$API_BASE/events")

    if [[ "$query_type" == "id" ]]; then
        result=$(echo "$response" | jq ".events[] | select(.id == $query_value)")
    else
        result=$(echo "$response" | jq ".events[] | select(.identifier == \"$query_value\")")
    fi

    if [[ -z "$result" || "$result" == "null" ]]; then
        echo "No outage found with $query_type = $query_value"
        exit 1
    fi

    print_outage "$result" ""
fi
