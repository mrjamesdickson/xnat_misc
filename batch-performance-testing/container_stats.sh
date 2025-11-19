#!/usr/bin/env bash

# XNAT Container Statistics Summary
# Generates summary statistics of running and recent containers across all projects

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
DAYS=1
SHOW_DETAILS=false

# Usage
usage() {
    echo "Usage: $0 -h <XNAT_HOST> -u <USERNAME> -p <PASSWORD> [-d <DAYS>] [-v]"
    echo ""
    echo "  -h  XNAT host (e.g., https://xnat.example.com)"
    echo "  -u  Username"
    echo "  -p  Password"
    echo "  -d  Days of history to include (default: 1)"
    echo "  -v  Verbose mode - show detailed workflow list"
    echo ""
    echo "Example:"
    echo "  $0 -h http://demo02.xnatworks.io -u admin -p admin -d 7"
    exit 1
}

# Parse arguments
while getopts "h:u:p:d:v" opt; do
    case $opt in
        h) XNAT_HOST="$OPTARG" ;;
        u) USERNAME="$OPTARG" ;;
        p) PASSWORD="$OPTARG" ;;
        d) DAYS="$OPTARG" ;;
        v) SHOW_DETAILS=true ;;
        *) usage ;;
    esac
done

if [ -z "${XNAT_HOST:-}" ] || [ -z "${USERNAME:-}" ] || [ -z "${PASSWORD:-}" ]; then
    usage
fi

# Remove trailing slash from host
XNAT_HOST="${XNAT_HOST%/}"

echo -e "${CYAN}=== XNAT Container Statistics ===${NC}"
echo "Host: $XNAT_HOST"
echo "Time window: Last $DAYS day(s)"
echo ""

# Authenticate
echo -e "${YELLOW}Authenticating...${NC}"
JSESSION=$(curl -s -u "${USERNAME}:${PASSWORD}" "${XNAT_HOST}/data/JSESSION")

if [ -z "$JSESSION" ]; then
    echo -e "${RED}Failed to authenticate${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Authenticated${NC}"
echo ""

# Get all projects
echo -e "${YELLOW}Fetching projects...${NC}"
PROJECTS=$(curl -s -b "JSESSIONID=$JSESSION" "${XNAT_HOST}/data/projects" | \
    jq -r '.ResultSet.Result[].ID' 2>/dev/null || echo "")

if [ -z "$PROJECTS" ]; then
    echo -e "${RED}No projects found${NC}"
    exit 1
fi

PROJECT_COUNT=$(echo "$PROJECTS" | wc -l | tr -d ' ')
echo -e "${GREEN}✓ Found $PROJECT_COUNT project(s)${NC}"
echo ""

# Fetch workflows from all projects
echo -e "${YELLOW}Fetching workflows...${NC}"
ALL_WORKFLOWS="[]"

for project in $PROJECTS; do
    PROJECT_WORKFLOWS=$(curl -s -X POST \
        -b "JSESSIONID=$JSESSION" \
        -H "Content-Type: application/json" \
        -H "X-Requested-With: XMLHttpRequest" \
        "${XNAT_HOST}/xapi/workflows" \
        -d "{\"id\":\"$project\",\"data_type\":\"xnat:projectData\",\"sortable\":true,\"days\":$DAYS}" 2>/dev/null)

    if [ -n "$PROJECT_WORKFLOWS" ]; then
        PROJECT_ITEMS=$(echo "$PROJECT_WORKFLOWS" | jq 'if type == "array" then . else .items // .workflows // [] end' 2>/dev/null || echo "[]")
        ALL_WORKFLOWS=$(echo "$ALL_WORKFLOWS" "$PROJECT_ITEMS" | jq -s '.[0] + .[1]' 2>/dev/null || echo "$ALL_WORKFLOWS")
    fi
done

TOTAL_WORKFLOWS=$(echo "$ALL_WORKFLOWS" | jq 'length' 2>/dev/null || echo "0")

if [ "$TOTAL_WORKFLOWS" -eq 0 ]; then
    echo -e "${YELLOW}No workflows found in the last $DAYS day(s)${NC}"
    exit 0
fi

echo -e "${GREEN}✓ Found $TOTAL_WORKFLOWS workflow(s)${NC}"
echo ""

# Generate statistics
echo -e "${CYAN}=== Summary Statistics ===${NC}"
echo ""

# Count by status
echo "Status Breakdown:"
echo "$ALL_WORKFLOWS" | jq -r '
    group_by(.status) |
    map({status: .[0].status, count: length}) |
    sort_by(-.count) |
    .[] |
    "  \(.status): \(.count)"
' 2>/dev/null || echo "  Unable to parse statuses"
echo ""

# Count by container/pipeline
echo "Container Breakdown:"
echo "$ALL_WORKFLOWS" | jq -r '
    group_by(.pipelineName // .pipeline_name // "unknown") |
    map({container: .[0].pipelineName // .[0].pipeline_name // "unknown", count: length}) |
    sort_by(-.count) |
    .[] |
    "  \(.container): \(.count)"
' 2>/dev/null || echo "  Unable to parse containers"
echo ""

# Count by project
echo "Project Breakdown:"
echo "$ALL_WORKFLOWS" | jq -r '
    group_by(.externalId // .external_id // "unknown") |
    map({project: .[0].externalId // .[0].external_id // "unknown", count: length}) |
    sort_by(-.count) |
    .[] |
    "  \(.project): \(.count)"
' 2>/dev/null || echo "  Unable to parse projects"
echo ""

# Active vs completed
RUNNING=$(echo "$ALL_WORKFLOWS" | jq '[.[] | select(.status | test("Running|Started|In Progress|Queued|Pending"; "i"))] | length' 2>/dev/null || echo "0")
COMPLETE=$(echo "$ALL_WORKFLOWS" | jq '[.[] | select(.status | test("Complete"; "i"))] | length' 2>/dev/null || echo "0")
FAILED=$(echo "$ALL_WORKFLOWS" | jq '[.[] | select(.status | test("Failed|Killed"; "i"))] | length' 2>/dev/null || echo "0")

echo "Activity Summary:"
echo "  Active (Running/Queued): $RUNNING"
echo "  Completed: $COMPLETE"
echo "  Failed: $FAILED"
echo ""

# Show detailed list if verbose
if [ "$SHOW_DETAILS" = true ]; then
    echo -e "${CYAN}=== Detailed Workflow List ===${NC}"
    echo ""

    echo "$ALL_WORKFLOWS" | jq -r '
        sort_by(.launchTime // .launch_time // 0) |
        reverse |
        .[] |
        [
            (.workflowId // .workflow_id // .wfid // "N/A"),
            (.externalId // .external_id // "N/A"),
            (.pipelineName // .pipeline_name // "N/A"),
            .status,
            ((.launchTime // .launch_time // 0) / 1000 | strftime("%Y-%m-%d %H:%M:%S"))
        ] |
        @tsv
    ' | column -t -s $'\t' -N "Workflow ID,Project,Container,Status,Launch Time" 2>/dev/null || \
        echo "Unable to format workflow details"
    echo ""
fi

echo -e "${GREEN}✓ Statistics complete${NC}"
