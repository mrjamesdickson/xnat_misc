#!/bin/bash

# Workflow Status Checker
# Checks XNAT workflow table for recent jobs

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Usage
usage() {
    echo "Usage: $0 -h <XNAT_HOST> -u <USERNAME> -p <PASSWORD> [-j <PROJECT_ID>] [-n <COUNT>]"
    echo "  -h  XNAT host (e.g., https://xnat.example.com)"
    echo "  -u  Username"
    echo "  -p  Password"
    echo "  -j  Project ID (optional - filters to project)"
    echo "  -n  Number of recent workflows to show (default: 50)"
    exit 1
}

# Parse arguments
PROJECT_ID=""
LIMIT=50
while getopts "h:u:p:j:n:" opt; do
    case $opt in
        h) XNAT_HOST="$OPTARG" ;;
        u) USERNAME="$OPTARG" ;;
        p) PASSWORD="$OPTARG" ;;
        j) PROJECT_ID="$OPTARG" ;;
        n) LIMIT="$OPTARG" ;;
        *) usage ;;
    esac
done

if [ -z "$XNAT_HOST" ] || [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
    usage
fi

# Remove trailing slash from host
XNAT_HOST="${XNAT_HOST%/}"

# Authenticate
JSESSION=$(curl -s -u "${USERNAME}:${PASSWORD}" "${XNAT_HOST}/data/JSESSION")

if [ -z "$JSESSION" ]; then
    echo -e "${RED}Failed to authenticate${NC}"
    exit 1
fi

echo -e "${GREEN}=== XNAT Workflows ===${NC}"
echo "Host: $XNAT_HOST"
if [ -n "$PROJECT_ID" ]; then
    echo "Project: $PROJECT_ID"
fi
echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Get workflows
echo -e "${YELLOW}Fetching recent workflows...${NC}"

if [ -n "$PROJECT_ID" ]; then
    WORKFLOWS=$(curl -s -b "JSESSIONID=$JSESSION" "${XNAT_HOST}/data/projects/${PROJECT_ID}/workflows?format=json" 2>/dev/null)
else
    WORKFLOWS=$(curl -s -b "JSESSIONID=$JSESSION" "${XNAT_HOST}/data/workflows?format=json" 2>/dev/null)
fi

if [ $? -ne 0 ] || [ -z "$WORKFLOWS" ]; then
    echo -e "${RED}Failed to fetch workflows${NC}"
    exit 1
fi

# Parse and display workflows
TOTAL=$(echo "$WORKFLOWS" | jq '.ResultSet.totalRecords // 0' 2>/dev/null)
echo -e "${BLUE}Total workflows: $TOTAL${NC}"
echo ""

# Get recent workflows sorted by launch_time
echo -e "${YELLOW}Recent $LIMIT workflows:${NC}"
echo ""
printf "%-12s %-20s %-25s %-20s %-20s\n" "ID" "Status" "Pipeline" "Launch Time" "Step"

echo "$WORKFLOWS" | jq -r --arg limit "$LIMIT" '
    .ResultSet.Result // [] |
    sort_by(.launch_time) | reverse |
    .[:($limit|tonumber)] |
    .[] |
    [
        .workflow_id // .ID // "unknown",
        .status // "unknown",
        .pipeline_name // .data_type // "unknown",
        (.launch_time // "unknown" | if type == "string" then split(".")[0] | gsub("T"; " ") else . end),
        .step_description // .current_step_id // ""
    ] |
    @tsv
' | while IFS=$'\t' read -r wf_id status pipeline launch_time step_desc; do
    case "$status" in
        *[Cc]omplete*|*[Dd]one*)
            printf "${GREEN}%-12s %-20s${NC} %-25s %-20s %-20s\n" "$wf_id" "$status" "$pipeline" "$launch_time" "$step_desc"
            ;;
        *[Ff]ail*|*[Ee]rror*)
            printf "${RED}%-12s %-20s${NC} %-25s %-20s %-20s\n" "$wf_id" "$status" "$pipeline" "$launch_time" "$step_desc"
            ;;
        *[Rr]unning*|*[Pp]ending*|*[Qq]ueued*)
            printf "${YELLOW}%-12s %-20s${NC} %-25s %-20s %-20s\n" "$wf_id" "$status" "$pipeline" "$launch_time" "$step_desc"
            ;;
        *)
            printf "%-12s %-20s %-25s %-20s %-20s\n" "$wf_id" "$status" "$pipeline" "$launch_time" "$step_desc"
            ;;
    esac
done

echo ""

# Status summary
echo -e "${YELLOW}Status Summary:${NC}"
echo "$WORKFLOWS" | jq -r '.ResultSet.Result // [] | group_by(.status) | .[] | "\(.[0].status): \(length)"' | while read -r line; do
    status=$(echo "$line" | cut -d: -f1)
    count=$(echo "$line" | cut -d: -f2)
    case "$status" in
        *[Cc]omplete*|*[Dd]one*)
            echo -e "  ${GREEN}✓ $count${NC} $status"
            ;;
        *[Ff]ail*|*[Ee]rror*)
            echo -e "  ${RED}✗ $count${NC} $status"
            ;;
        *[Rr]unning*|*[Pp]ending*|*[Qq]ueued*)
            echo -e "  ${YELLOW}⚠ $count${NC} $status"
            ;;
        *)
            echo -e "  ${BLUE}• $count${NC} $status"
            ;;
    esac
done
