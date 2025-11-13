#!/bin/bash

# Simple Workflow Checker - shows recent workflow activity
# Based on XNAT User Dashboard view

XNAT_HOST="${1:-http://demo02.xnatworks.io}"
USERNAME="${2:-admin}"
PASSWORD="${3:-admin}"
PROJECT="${4}"
LIMIT="${5:-100}"

# Authenticate
JSESSION=$(curl -s -u "${USERNAME}:${PASSWORD}" "${XNAT_HOST}/data/JSESSION")

echo "=== XNAT Workflow Status ==="
echo "Host: $XNAT_HOST"
echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Get workflows - site-wide or project-specific
if [ -n "$PROJECT" ]; then
    echo "Project: $PROJECT"
    URL="${XNAT_HOST}/data/projects/${PROJECT}/experiments?format=json"
else
    URL="${XNAT_HOST}/data/experiments?format=json"
fi

# Get recent experiments with workflow data
EXPERIMENTS=$(curl -s -b "JSESSIONID=$JSESSION" "$URL")

# Parse and display
echo "$EXPERIMENTS" | jq -r --arg limit "$LIMIT" '
    .ResultSet.Result // [] |
    map(select(.pipeline_name != null)) |
    sort_by(.insert_date // .last_modified) | reverse |
    .[:($limit|tonumber)] |
    .[] |
    [
        .project // "unknown",
        .label // .ID // "unknown",
        .pipeline_name // "unknown",
        (.insert_date // .last_modified // "unknown" | if type == "string" then split(".")[0] | gsub("T"; " ") else . end),
        "Complete"
    ] |
    @tsv
' | head -50 | column -t -s $'\t'
