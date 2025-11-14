#!/bin/bash

# Container Status Checker
# Monitors container job status for a project

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Usage
usage() {
    echo "Usage: $0 -h <XNAT_HOST> -u <USERNAME> -p <PASSWORD> -j <PROJECT_ID> [-w] [-r <RANGE>]"
    echo "  -h  XNAT host (e.g., https://xnat.example.com)"
    echo "  -u  Username"
    echo "  -p  Password"
    echo "  -j  Project ID"
    echo "  -w  Watch mode (refresh every 10 seconds)"
    echo "  -r  Date range: today, week, month, all (default: today)"
    exit 1
}

# Parse arguments
WATCH_MODE=false
DATE_RANGE="today"
while getopts "h:u:p:j:r:w" opt; do
    case $opt in
        h) XNAT_HOST="$OPTARG" ;;
        u) USERNAME="$OPTARG" ;;
        p) PASSWORD="$OPTARG" ;;
        j) PROJECT_ID="$OPTARG" ;;
        r) DATE_RANGE="$OPTARG" ;;
        w) WATCH_MODE=true ;;
        *) usage ;;
    esac
done

if [ -z "$XNAT_HOST" ] || [ -z "$USERNAME" ] || [ -z "$PASSWORD" ] || [ -z "$PROJECT_ID" ]; then
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

check_status() {
    clear
    echo -e "${GREEN}=== Workflow Status: $PROJECT_ID ===${NC}"
    echo "Host: $XNAT_HOST"
    echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Range: $DATE_RANGE"
    echo ""

    # Calculate date cutoff based on range
    case "$DATE_RANGE" in
        today)
            CUTOFF_DATE=$(date -u -v-0d '+%Y-%m-%dT00:00:00' 2>/dev/null || date -u -d 'today 00:00:00' '+%Y-%m-%dT%H:%M:%S' 2>/dev/null)
            ;;
        week)
            CUTOFF_DATE=$(date -u -v-7d '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date -u -d '7 days ago' '+%Y-%m-%dT%H:%M:%S' 2>/dev/null)
            ;;
        month)
            CUTOFF_DATE=$(date -u -v-30d '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date -u -d '30 days ago' '+%Y-%m-%dT%H:%M:%S' 2>/dev/null)
            ;;
        *)
            CUTOFF_DATE=""
            ;;
    esac

    # Get workflows using the correct POST endpoint (as used by XNAT UI)
    echo -e "${YELLOW}Fetching workflow data (paginated)...${NC}"

    # Calculate days parameter based on date range
    case "$DATE_RANGE" in
        today) DAYS=1 ;;
        week) DAYS=7 ;;
        month) DAYS=30 ;;
        *) DAYS=365 ;;
    esac

    # Fetch all pages (API returns 50 results per page)
    ALL_WORKFLOWS="[]"
    PAGE=1
    while true; do
        echo -ne "\r${YELLOW}Fetching page $PAGE...${NC}  "

        # Build POST payload for workflows query
        WORKFLOW_QUERY="{\"page\":$PAGE,\"id\":\"$PROJECT_ID\",\"data_type\":\"xnat:projectData\",\"sortable\":true,\"days\":$DAYS}"

        WORKFLOWS=$(curl -s -X POST \
            -b "JSESSIONID=$JSESSION" \
            -H "Content-Type: application/json" \
            -H "X-Requested-With: XMLHttpRequest" \
            --max-time 30 \
            "${XNAT_HOST}/xapi/workflows" \
            -d "$WORKFLOW_QUERY" 2>/dev/null)

        if [ $? -ne 0 ] || [ -z "$WORKFLOWS" ]; then
            echo -e "\r${RED}Failed to fetch workflow status on page $PAGE${NC}"
            break
        fi

        # Check if response is HTML (error) or JSON
        if echo "$WORKFLOWS" | grep -q "<!doctype html"; then
            echo -e "\r${RED}Authentication error or API unavailable${NC}"
            break
        fi

        # Extract workflow results (the response is an array)
        if echo "$WORKFLOWS" | jq -e 'type == "array"' > /dev/null 2>&1; then
            PAGE_WORKFLOWS="$WORKFLOWS"
        else
            PAGE_WORKFLOWS=$(echo "$WORKFLOWS" | jq '.items // .workflows // []' 2>/dev/null)
        fi

        # Check if we got any results
        PAGE_COUNT=$(echo "$PAGE_WORKFLOWS" | jq 'length' 2>/dev/null)

        if [ -z "$PAGE_COUNT" ] || [ "$PAGE_COUNT" -eq 0 ]; then
            # No more results
            break
        fi

        # Append to all workflows
        ALL_WORKFLOWS=$(echo "$ALL_WORKFLOWS" "$PAGE_WORKFLOWS" | jq -s '.[0] + .[1]' 2>/dev/null)

        # If we got less than 50 results, we're done
        if [ "$PAGE_COUNT" -lt 50 ]; then
            break
        fi

        PAGE=$((PAGE + 1))
    done

    echo -e "\r${YELLOW}Fetched all workflow pages.${NC}                    "

    if [ -z "$ALL_WORKFLOWS" ] || [ "$ALL_WORKFLOWS" = "null" ] || [ "$ALL_WORKFLOWS" = "[]" ]; then
        echo -e "${RED}No workflow data received${NC}"
        return 1
    fi

    # The API already filtered by days parameter, just sort by launch_time descending
    FILTERED_WORKFLOWS=$(echo "$ALL_WORKFLOWS" | jq 'sort_by(.launchTime // .launch_time) | reverse')

    TOTAL=$(echo "$FILTERED_WORKFLOWS" | jq 'length' 2>/dev/null)

    echo -e "${BLUE}Total workflows (last $DAYS days): $TOTAL${NC}"
    echo ""

    # Count workflows by status
    echo -e "${YELLOW}Status Summary:${NC}"
    echo "$FILTERED_WORKFLOWS" | jq -r '.[].status' 2>/dev/null | sort | uniq -c | sort -rn | while read -r count status; do
        case "$status" in
            *[Rr]unning*|*[Ss]tarted*)
                echo -e "  ${YELLOW}⚠ $count${NC} $status"
                ;;
            *[Cc]omplete*|*[Ss]uccess*|*[Dd]one*)
                echo -e "  ${GREEN}✓ $count${NC} $status"
                ;;
            *[Ff]ail*|*[Ee]rror*)
                echo -e "  ${RED}✗ $count${NC} $status"
                ;;
            *[Qq]ueued*|*[Pp]ending*)
                echo -e "  ${BLUE}• $count${NC} $status"
                ;;
            *)
                echo -e "  ${BLUE}• $count${NC} $status"
                ;;
        esac
    done

    echo ""
    echo -e "${YELLOW}Status by Pipeline:${NC}"
    echo "$FILTERED_WORKFLOWS" | jq -r '.[] | "\(.pipeline_name // .data_type // "unknown")\t\(.status)"' 2>/dev/null | sort | uniq -c | sort -rn | head -20 | while read -r count pipeline status; do
        printf "  %3s  %-30s  %s\n" "$count" "$pipeline" "$status"
    done

    echo ""
    echo -e "${YELLOW}Recent Workflows (last 20):${NC}"
    printf "%-4s %-15s %-20s %-20s %-19s %-10s\n" "No." "Status" "Wrapper" "Experiment" "Launch Time" "Progress"
    echo "$FILTERED_WORKFLOWS" | jq -r '.[] | "\(.status // "unknown")\t\(.name // .pipelineName // "unknown")\t\(.label // .experimentLabel // "unknown")\t\(.launchTime // .launch_time // "unknown")\t\(.percentComplete // .percentagecomplete // 100)%"' 2>/dev/null | head -20 | while IFS=$'\t' read -r status wrapper exp_label launch_time progress; do
        # Format timestamp (convert Unix timestamp in milliseconds to date if numeric)
        if [[ "$launch_time" =~ ^[0-9]+$ ]]; then
            # Convert milliseconds to seconds for date command
            launch_sec=$((launch_time / 1000))
            launch_fmt=$(date -r "$launch_sec" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -d "@$launch_sec" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$launch_time")
        else
            launch_fmt=$(echo "$launch_time" | sed 's/\.[0-9]*+0000//' | sed 's/T/ /' | cut -c1-19)
        fi

        case "$status" in
            *[Rr]unning*|*[Ss]tarted*)
                printf "${YELLOW}%-4s %-15s${NC} %-20s %-20s %-19s %-10s\n" "" "$status" "$wrapper" "$exp_label" "$launch_fmt" "$progress"
                ;;
            *[Cc]omplete*|*[Ss]uccess*|*[Dd]one*)
                printf "${GREEN}%-4s %-15s${NC} %-20s %-20s %-19s %-10s\n" "" "$status" "$wrapper" "$exp_label" "$launch_fmt" "$progress"
                ;;
            *[Ff]ail*|*[Ee]rror*)
                printf "${RED}%-4s %-15s${NC} %-20s %-20s %-19s %-10s\n" "" "$status" "$wrapper" "$exp_label" "$launch_fmt" "$progress"
                ;;
            *)
                printf "${BLUE}%-4s %-15s${NC} %-20s %-20s %-19s %-10s\n" "" "$status" "$wrapper" "$exp_label" "$launch_fmt" "$progress"
                ;;
        esac
    done | nl -w 3 -s '. '
}

# Main loop
if [ "$WATCH_MODE" = true ]; then
    echo -e "${BLUE}Watch mode enabled. Press Ctrl+C to exit.${NC}"
    while true; do
        check_status
        sleep 10
    done
else
    check_status
fi
