#!/bin/bash

# Debug script to see container data structure

XNAT_HOST="${1:-http://demo02.xnatworks.io}"
USERNAME="${2:-admin}"
PASSWORD="${3:-admin}"
PROJECT="${4:-TOTALSEGMENTATOR}"

echo "Authenticating..."
JSESSION=$(curl -s -u "${USERNAME}:${PASSWORD}" "${XNAT_HOST}/data/JSESSION")

echo "Fetching first container from project $PROJECT..."
CONTAINER=$(curl -s -b "JSESSIONID=$JSESSION" "${XNAT_HOST}/xapi/projects/${PROJECT}/containers?limit=1")

echo ""
echo "=== Container Fields ==="
echo "$CONTAINER" | jq '.[0] | keys' 2>/dev/null

echo ""
echo "=== Full Container Object ==="
echo "$CONTAINER" | jq '.[0]' 2>/dev/null
