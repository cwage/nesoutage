#!/bin/bash

# NES Outage Checker
# Query NES outage API by database ID (-i) or public reference number (-r)

API_URL="https://utilisocial.io/datacapable/v2/p/NES/map/events"

usage() {
    echo "Usage: $0 [-i <db_id>] [-r <reference_number>]"
    echo ""
    echo "Options:"
    echo "  -i <id>    Query by database ID (e.g., 1978957)"
    echo "  -r <ref>   Query by public reference/identifier (e.g., 2621583)"
    echo ""
    echo "Examples:"
    echo "  $0 -i 1978957"
    echo "  $0 -r 2621583"
    exit 1
}

format_timestamp() {
    local ts_ms="$1"
    local ts_sec=$((ts_ms / 1000))
    TZ="America/Chicago" date -d "@$ts_sec" "+%Y-%m-%d %I:%M:%S %p %Z"
}

query_type=""
query_value=""

while getopts "i:r:h" opt; do
    case $opt in
        i)
            query_type="id"
            query_value="$OPTARG"
            ;;
        r)
            query_type="identifier"
            query_value="$OPTARG"
            ;;
        h)
            usage
            ;;
        *)
            usage
            ;;
    esac
done

if [[ -z "$query_type" || -z "$query_value" ]]; then
    usage
fi

# Build jq filter based on query type
if [[ "$query_type" == "id" ]]; then
    jq_filter=".[] | select(.id == $query_value)"
else
    jq_filter=".[] | select(.identifier == \"$query_value\")"
fi

# Fetch and filter
result=$(curl -s "$API_URL" | jq "$jq_filter")

if [[ -z "$result" || "$result" == "null" ]]; then
    echo "No outage found with $query_type = $query_value"
    exit 1
fi

# Extract fields
id=$(echo "$result" | jq -r '.id')
identifier=$(echo "$result" | jq -r '.identifier')
title=$(echo "$result" | jq -r '.title')
status=$(echo "$result" | jq -r '.status')
num_people=$(echo "$result" | jq -r '.numPeople')
cause=$(echo "$result" | jq -r '.cause // "Not specified"')
start_time=$(echo "$result" | jq -r '.startTime')
last_updated=$(echo "$result" | jq -r '.lastUpdatedTime')
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
echo "  Location:         $latitude, $longitude"
echo "  Map:              https://www.google.com/maps?q=$latitude,$longitude"
echo ""
echo "═══════════════════════════════════════════════════════"
