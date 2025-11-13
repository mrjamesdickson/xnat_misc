#!/bin/bash

# Batch Performance Testing Script
# Tests container batch submission performance on largest project

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Usage
usage() {
    echo "Usage: $0 -h <XNAT_HOST> -u <USERNAME> -p <PASSWORD> [-c <CONTAINER_NAME>] [-m <MAX_JOBS>]"
    echo "  -h  XNAT host (e.g., https://xnat.example.com)"
    echo "  -u  Username"
    echo "  -p  Password"
    echo "  -c  Container name to run (optional - will list if not provided)"
    echo "  -m  Maximum number of jobs to submit (optional - defaults to all experiments)"
    exit 1
}

# Parse arguments
while getopts "h:u:p:c:m:" opt; do
    case $opt in
        h) XNAT_HOST="$OPTARG" ;;
        u) USERNAME="$OPTARG" ;;
        p) PASSWORD="$OPTARG" ;;
        c) CONTAINER_NAME="$OPTARG" ;;
        m) MAX_JOBS="$OPTARG" ;;
        *) usage ;;
    esac
done

if [ -z "$XNAT_HOST" ] || [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
    usage
fi

# Remove trailing slash from host
XNAT_HOST="${XNAT_HOST%/}"

echo -e "${GREEN}=== XNAT Batch Performance Testing ===${NC}"
echo "Host: $XNAT_HOST"
echo "User: $USERNAME"
echo ""

# Step 1: Authenticate
echo -e "${YELLOW}[1/5] Authenticating...${NC}"
JSESSION=$(curl -s -u "${USERNAME}:${PASSWORD}" "${XNAT_HOST}/data/JSESSION")

if [ -z "$JSESSION" ]; then
    echo -e "${RED}Failed to authenticate${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Authenticated (JSESSION: ${JSESSION:0:20}...)${NC}"
echo ""

# Step 2: Select project first
echo -e "${YELLOW}[2/5] Project selection...${NC}"
echo "Fetching projects and counting experiments..."
PROJECTS=$(curl -s -b "JSESSIONID=$JSESSION" "${XNAT_HOST}/data/projects?format=json")

# Get experiment counts for each project
PROJECT_COUNTS=$(echo "$PROJECTS" | jq -r '.ResultSet.Result[] | .ID' | while read -r PROJECT_ID; do
    EXP_COUNT=$(curl -s -b "JSESSIONID=$JSESSION" "${XNAT_HOST}/data/projects/${PROJECT_ID}/experiments?format=json" | jq -r '.ResultSet.totalRecords // 0')
    echo "$EXP_COUNT:$PROJECT_ID"
done | sort -rn)

echo ""
echo "Top 10 projects by experiment count:"
echo "$PROJECT_COUNTS" | head -10 | nl -w 3 -s '. ' | while IFS=':' read -r NUM COUNT_PROJECT; do
    COUNT=$(echo "$COUNT_PROJECT" | cut -d: -f1)
    PROJECT=$(echo "$COUNT_PROJECT" | cut -d: -f2)
    printf "%s %s (%s experiments)\n" "$NUM" "$PROJECT" "$COUNT"
done

echo ""
read -p "Enter project ID to use (or press Enter for largest): " SELECTED_PROJECT

if [ -z "$SELECTED_PROJECT" ]; then
    # Use largest project
    LARGEST_PROJECT=$(echo "$PROJECT_COUNTS" | head -1 | cut -d: -f2)
    echo "Using largest project: $LARGEST_PROJECT"
else
    LARGEST_PROJECT="$SELECTED_PROJECT"
fi

# Get experiment count for selected project
MAX_EXPERIMENTS=$(curl -s -b "JSESSIONID=$JSESSION" "${XNAT_HOST}/data/projects/${LARGEST_PROJECT}/experiments?format=json" | jq -r '.ResultSet.totalRecords // 0')

echo ""
echo -e "${GREEN}✓ Selected project: $LARGEST_PROJECT ($MAX_EXPERIMENTS experiments)${NC}"
echo ""

# Step 3: List/select container (filtered by selected project)
echo -e "${YELLOW}[3/5] Container selection...${NC}"
if [ -z "$CONTAINER_NAME" ]; then
    echo "Fetching available containers for project ${LARGEST_PROJECT}..."

    # Try multiple endpoints for container commands
    COMMANDS=""
    for endpoint in "/xapi/commands" "/data/services/containers/commands" "/REST/services/containers/commands"; do
        COMMANDS=$(curl -s -b "JSESSIONID=$JSESSION" "${XNAT_HOST}${endpoint}" -H "Accept: application/json")

        # Check if valid JSON and not 404
        if echo "$COMMANDS" | jq empty 2>/dev/null && [ "$COMMANDS" != "[]" ] && [ "$COMMANDS" != "null" ]; then
            echo "Using endpoint: ${endpoint}"
            break
        fi
        COMMANDS=""
    done

    # Debug: Check response
    if [ -z "$COMMANDS" ]; then
        echo -e "${RED}No container service found. Tried endpoints:${NC}"
        echo "  - /xapi/commands"
        echo "  - /data/services/containers/commands"
        echo "  - /REST/services/containers/commands"
        echo ""
        echo -e "${YELLOW}Note: Container service may not be installed or enabled.${NC}"
        echo "You can still specify a wrapper ID if you know it."
        echo ""
        read -p "Enter wrapper ID (or press Ctrl+C to exit): " CONTAINER_NAME

        if [ -z "$CONTAINER_NAME" ]; then
            echo -e "${RED}No container specified${NC}"
            exit 1
        fi
    else
        # Extract wrappers from commands and check if enabled for selected project
        echo ""
        echo "Containers available for project ${LARGEST_PROJECT}:"
        echo -e "ID\tName\tStatus\tContexts" > /tmp/wrappers_$$.txt

        echo "$COMMANDS" | jq -r '
            .[] |
            (.xnat // .["xnat-command-wrappers"] // .xnatCommandWrappers // [])[] |
            "\(.id)\t\(.name)\t\(.contexts | join(","))"
        ' | while IFS=$'\t' read -r wrapper_id wrapper_name contexts; do
            # Check if this wrapper is enabled for the selected project
            enabled_resp=$(curl -s -b "JSESSIONID=$JSESSION" "${XNAT_HOST}/xapi/projects/${LARGEST_PROJECT}/wrappers/${wrapper_id}/enabled" 2>/dev/null)

            # Parse response (JSON or plain text)
            if echo "$enabled_resp" | jq empty 2>/dev/null; then
                enabled=$(echo "$enabled_resp" | jq -r '.["enabled-for-project"] // false')
            else
                enabled="$enabled_resp"
            fi

            if [ "$enabled" = "true" ]; then
                echo -e "$wrapper_id\t$wrapper_name\tenabled\t$contexts" >> /tmp/wrappers_$$.txt
            else
                echo -e "$wrapper_id\t$wrapper_name\tdisabled\t$contexts" >> /tmp/wrappers_$$.txt
            fi
        done

        # Show enabled wrappers first, then disabled
        echo -e "${GREEN}Enabled:${NC}"
        grep -E "\tenabled\t" /tmp/wrappers_$$.txt | column -t -s $'\t' | nl -w 3 -s '. ' || echo "  (none)"
        echo ""
        echo -e "${YELLOW}Disabled (site-level only):${NC}"
        grep -E "\tdisabled\t" /tmp/wrappers_$$.txt | column -t -s $'\t' | nl -w 3 -s '. ' || echo "  (none)"

        rm /tmp/wrappers_$$.txt
        echo ""

        read -p "Enter wrapper name or ID: " CONTAINER_NAME

        if [ -z "$CONTAINER_NAME" ]; then
            echo -e "${RED}No container specified${NC}"
            exit 1
        fi
    fi
fi

echo -e "${GREEN}✓ Container: $CONTAINER_NAME${NC}"
echo ""

# Verify/enable wrapper for selected project
echo -e "${YELLOW}Verifying wrapper is enabled for project ${LARGEST_PROJECT}...${NC}"

# If COMMANDS not already fetched, fetch it
if [ -z "$COMMANDS" ]; then
    COMMANDS=$(curl -s -b "JSESSIONID=$JSESSION" "${XNAT_HOST}/xapi/commands" -H "Accept: application/json")
fi

# Search for wrapper by name or ID in all commands
WRAPPER_ID=$(echo "$COMMANDS" | jq -r --arg name "$CONTAINER_NAME" '
    .[] |
    (.xnat // .["xnat-command-wrappers"] // .xnatCommandWrappers // [])[] |
    select(.name == $name or (.id|tostring) == $name) |
    .id
' | head -1)

if [ -z "$WRAPPER_ID" ]; then
    # If not found, assume CONTAINER_NAME is the wrapper ID
    WRAPPER_ID="$CONTAINER_NAME"
fi

# Check if enabled for this project
ENABLED_RESPONSE=$(curl -s -b "JSESSIONID=$JSESSION" "${XNAT_HOST}/xapi/projects/${LARGEST_PROJECT}/wrappers/${WRAPPER_ID}/enabled" 2>/dev/null)

# Check if response is JSON (newer XNAT) or plain text (older XNAT)
if echo "$ENABLED_RESPONSE" | jq empty 2>/dev/null; then
    # JSON response
    ENABLED=$(echo "$ENABLED_RESPONSE" | jq -r '.["enabled-for-project"] // false')
else
    # Plain text response
    ENABLED="$ENABLED_RESPONSE"
fi

if [ "$ENABLED" != "true" ]; then
    echo -e "${YELLOW}Wrapper is not enabled for project ${LARGEST_PROJECT}${NC}"
    read -p "Enable wrapper for this project? (y/yes): " ENABLE_CONFIRM

    if [[ "$ENABLE_CONFIRM" =~ ^[Yy]([Ee][Ss])?$ ]]; then
        echo "Enabling wrapper ${WRAPPER_ID} for project ${LARGEST_PROJECT}..."

        # Enable the wrapper for the project
        ENABLE_RESULT=$(curl -s -X PUT \
            -b "JSESSIONID=$JSESSION" \
            -H "Content-Type: text/plain" \
            "${XNAT_HOST}/xapi/projects/${LARGEST_PROJECT}/wrappers/${WRAPPER_ID}/enabled" \
            -d "true")

        # Verify it was enabled
        VERIFY_RESPONSE=$(curl -s -b "JSESSIONID=$JSESSION" "${XNAT_HOST}/xapi/projects/${LARGEST_PROJECT}/wrappers/${WRAPPER_ID}/enabled" 2>/dev/null)

        # Check verification response
        if echo "$VERIFY_RESPONSE" | jq empty 2>/dev/null; then
            ENABLED_CHECK=$(echo "$VERIFY_RESPONSE" | jq -r '.["enabled-for-project"] // false')
        else
            ENABLED_CHECK="$VERIFY_RESPONSE"
        fi

        if [ "$ENABLED_CHECK" = "true" ]; then
            echo -e "${GREEN}✓ Wrapper enabled successfully${NC}"
        else
            echo -e "${RED}✗ Failed to enable wrapper${NC}"
            echo "Response: $VERIFY_RESPONSE"
            exit 1
        fi
    else
        echo -e "${RED}Wrapper must be enabled to proceed${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ Wrapper is enabled for project${NC}"
fi

echo ""

# Step 4: Get experiment list
echo -e "${YELLOW}[4/5] Retrieving experiments from $LARGEST_PROJECT...${NC}"
EXPERIMENTS=$(curl -s -b "JSESSIONID=$JSESSION" "${XNAT_HOST}/data/projects/${LARGEST_PROJECT}/experiments?format=json")
EXPERIMENT_IDS=$(echo "$EXPERIMENTS" | jq -r '.ResultSet.Result[] | .ID')
TOTAL_EXPERIMENT_COUNT=$(echo "$EXPERIMENT_IDS" | wc -l | tr -d ' ')

# Apply max jobs limit if specified
if [ -n "$MAX_JOBS" ] && [ "$MAX_JOBS" -gt 0 ]; then
    if [ "$MAX_JOBS" -lt "$TOTAL_EXPERIMENT_COUNT" ]; then
        EXPERIMENT_IDS=$(echo "$EXPERIMENT_IDS" | head -n "$MAX_JOBS")
        EXPERIMENT_COUNT="$MAX_JOBS"
        echo -e "${GREEN}✓ Retrieved $TOTAL_EXPERIMENT_COUNT experiments (limiting to $MAX_JOBS)${NC}"
    else
        EXPERIMENT_COUNT="$TOTAL_EXPERIMENT_COUNT"
        echo -e "${GREEN}✓ Retrieved $EXPERIMENT_COUNT experiments${NC}"
    fi
else
    EXPERIMENT_COUNT="$TOTAL_EXPERIMENT_COUNT"
    echo -e "${GREEN}✓ Retrieved $EXPERIMENT_COUNT experiments${NC}"
fi

echo ""
echo "First 10 experiments:"
echo "$EXPERIMENT_IDS" | head -10
echo ""

# Step 4: Confirm before batch submission
echo -e "${YELLOW}=== READY TO SUBMIT BATCH ===${NC}"
echo "Project: $LARGEST_PROJECT"
echo "Experiments: $EXPERIMENT_COUNT"
echo "Container: $CONTAINER_NAME"
echo ""
echo -e "${RED}This will create $EXPERIMENT_COUNT container jobs!${NC}"
echo ""
read -p "Continue with batch submission? (y/yes): " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    echo "Aborted."
    exit 0
fi

# Step 5: Show batch command syntax for confirmation
echo ""
echo -e "${YELLOW}[5/5] Batch submission command syntax:${NC}"
echo ""
echo "For each experiment, the following API call will be made:"
echo ""
echo "  curl -X POST \\"
echo "    -b \"JSESSIONID=<SESSION>\" \\"
echo "    -H \"Content-Type: application/x-www-form-urlencoded\" \\"
echo "    \"${XNAT_HOST}/xapi/wrappers/<WRAPPER_ID>/root/xnat:imageSessionData/launch\" \\"
echo "    -d \"context=session&session=<EXPERIMENT_ID>\""
echo ""
echo -e "${YELLOW}Note: This requires the wrapper-id for container '${CONTAINER_NAME}'${NC}"
echo ""
read -p "Proceed with finding wrapper-id and submitting? (y/yes): " CONFIRM2

if [[ ! "$CONFIRM2" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    echo "Aborted."
    exit 0
fi

# Find wrapper ID for container
echo ""
echo -e "${YELLOW}Finding wrapper-id for container '${CONTAINER_NAME}'...${NC}"

# If COMMANDS not already fetched, fetch it
if [ -z "$COMMANDS" ]; then
    COMMANDS=$(curl -s -b "JSESSIONID=$JSESSION" "${XNAT_HOST}/xapi/commands" -H "Accept: application/json")
fi

# Search for wrapper by name or ID in all commands
WRAPPER_ID=$(echo "$COMMANDS" | jq -r --arg name "$CONTAINER_NAME" '
    .[] |
    (.xnat // .["xnat-command-wrappers"] // .xnatCommandWrappers // [])[] |
    select(.name == $name or (.id|tostring) == $name) |
    .id
' | head -1)

if [ -z "$WRAPPER_ID" ]; then
    echo -e "${RED}Wrapper '$CONTAINER_NAME' not found${NC}"
    echo ""
    echo "Available wrappers:"
    echo "$COMMANDS" | jq -r '
        .[] |
        (.xnat // .["xnat-command-wrappers"] // .xnatCommandWrappers // [])[] |
        "\(.id): \(.name)"
    '
    exit 1
fi

echo -e "${GREEN}✓ Found wrapper-id: $WRAPPER_ID${NC}"
echo ""

# Submit batch
echo -e "${YELLOW}Submitting batch jobs...${NC}"
echo ""
echo "Debug info:"
echo "  Project: $LARGEST_PROJECT"
echo "  Wrapper ID: $WRAPPER_ID"
echo "  Endpoint: ${XNAT_HOST}/xapi/projects/${LARGEST_PROJECT}/wrappers/${WRAPPER_ID}/root/xnat:imageSessionData/launch"
echo ""

# Test first experiment to verify the call works
FIRST_EXP=$(echo "$EXPERIMENT_IDS" | head -1)
echo "Testing with first experiment: $FIRST_EXP"
TEST_RESPONSE=$(curl -s -X POST \
    -b "JSESSIONID=$JSESSION" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    "${XNAT_HOST}/xapi/wrappers/${WRAPPER_ID}/root/xnat:imageSessionData/launch" \
    -d "context=session&session=${FIRST_EXP}")

echo ""
echo "Test response:"
echo "$TEST_RESPONSE" | jq '.' 2>/dev/null || echo "$TEST_RESPONSE"
echo ""

read -p "Test successful? Continue with batch? (y/yes): " CONTINUE_BATCH

if [[ ! "$CONTINUE_BATCH" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "Submitting batch..."

SUCCESS_COUNT=0
FAIL_COUNT=0
RESULTS_FILE="/tmp/batch_results_$$.txt"

echo "$EXPERIMENT_IDS" | while read -r EXP_ID; do
    # Use form data (not JSON) with context=session parameter
    RESPONSE=$(curl -s -X POST \
        -b "JSESSIONID=$JSESSION" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        "${XNAT_HOST}/xapi/wrappers/${WRAPPER_ID}/root/xnat:imageSessionData/launch" \
        -d "context=session&session=${EXP_ID}")

    # Check if response is HTML (error page) or JSON
    if echo "$RESPONSE" | grep -q "<!doctype html"; then
        echo -e "${RED}✗${NC} $EXP_ID: $(echo "$RESPONSE" | grep -oP '(?<=<title>)[^<]+' | head -1)"
        echo "FAIL" >> "$RESULTS_FILE"
    elif echo "$RESPONSE" | jq empty 2>/dev/null; then
        # Valid JSON response - check for success
        STATUS=$(echo "$RESPONSE" | jq -r '.status // "unknown"')
        if [ "$STATUS" = "success" ]; then
            WORKFLOW_ID=$(echo "$RESPONSE" | jq -r '.["workflow-id"] // "pending"')
            echo -e "${GREEN}✓${NC} $EXP_ID (workflow: $WORKFLOW_ID)"
            echo "SUCCESS" >> "$RESULTS_FILE"
        else
            ERROR_MSG=$(echo "$RESPONSE" | jq -r '.message // .error // "Unknown error"')
            echo -e "${RED}✗${NC} $EXP_ID: $ERROR_MSG"
            echo "FAIL" >> "$RESULTS_FILE"
        fi
    else
        echo -e "${RED}✗${NC} $EXP_ID: Invalid response"
        echo "FAIL" >> "$RESULTS_FILE"
    fi
done

# Count results from file (since while loop runs in subshell)
if [ -f "$RESULTS_FILE" ]; then
    SUCCESS_COUNT=$(grep -c "SUCCESS" "$RESULTS_FILE" 2>/dev/null || echo "0")
    FAIL_COUNT=$(grep -c "FAIL" "$RESULTS_FILE" 2>/dev/null || echo "0")
    rm "$RESULTS_FILE"
else
    SUCCESS_COUNT=0
    FAIL_COUNT=0
fi

echo ""
echo -e "${GREEN}=== COMPLETE ===${NC}"
echo "Success: $SUCCESS_COUNT"
echo "Failed: $FAIL_COUNT"
echo ""

# Offer to monitor job status
if [ "$SUCCESS_COUNT" -gt 0 ]; then
    echo ""
    read -p "Check workflow status? (y/yes): " MONITOR

    if [[ "$MONITOR" =~ ^[Yy]([Ee][Ss])?$ ]]; then
        echo ""
        echo -e "${YELLOW}Fetching workflow status (with pagination)...${NC}"
        echo ""

        # Fetch workflows with pagination (same logic as check_status.sh)
        ALL_WORKFLOWS="[]"
        PAGE=1
        MAX_PAGES=20

        while [ $PAGE -le $MAX_PAGES ]; do
            echo -ne "\r${YELLOW}Fetching page $PAGE...${NC}  "

            WORKFLOW_QUERY="{\"page\":$PAGE,\"id\":\"$LARGEST_PROJECT\",\"data_type\":\"xnat:projectData\",\"sortable\":true,\"days\":1}"

            WORKFLOWS=$(curl -s -X POST \
                -b "JSESSIONID=$JSESSION" \
                -H "Content-Type: application/json" \
                -H "X-Requested-With: XMLHttpRequest" \
                --max-time 30 \
                "${XNAT_HOST}/xapi/workflows" \
                -d "$WORKFLOW_QUERY" 2>/dev/null)

            if [ $? -ne 0 ] || [ -z "$WORKFLOWS" ]; then
                break
            fi

            if echo "$WORKFLOWS" | grep -q "<!doctype html"; then
                break
            fi

            if echo "$WORKFLOWS" | jq -e 'type == "array"' > /dev/null 2>&1; then
                PAGE_WORKFLOWS="$WORKFLOWS"
            else
                PAGE_WORKFLOWS=$(echo "$WORKFLOWS" | jq '.items // .workflows // []' 2>/dev/null)
            fi

            PAGE_COUNT=$(echo "$PAGE_WORKFLOWS" | jq 'length' 2>/dev/null)

            if [ -z "$PAGE_COUNT" ] || [ "$PAGE_COUNT" -eq 0 ]; then
                break
            fi

            ALL_WORKFLOWS=$(echo "$ALL_WORKFLOWS" "$PAGE_WORKFLOWS" | jq -s '.[0] + .[1]' 2>/dev/null)

            if [ "$PAGE_COUNT" -lt 50 ]; then
                break
            fi

            PAGE=$((PAGE + 1))
        done

        echo -e "\r${YELLOW}Fetched all workflow pages.${NC}                    "
        echo ""

        TOTAL_WORKFLOWS=$(echo "$ALL_WORKFLOWS" | jq 'length' 2>/dev/null)

        if [ "$TOTAL_WORKFLOWS" -gt 0 ]; then
            echo -e "${BLUE}Total workflows (today): $TOTAL_WORKFLOWS${NC}"
            echo ""

            # Count workflows by status
            echo "Workflow Status Summary:"
            echo "$ALL_WORKFLOWS" | jq -r '.[].status' 2>/dev/null | sort | uniq -c | sort -rn | while read -r count status; do
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
                    *)
                        echo -e "  ${BLUE}• $count${NC} $status"
                        ;;
                esac
            done

            echo ""
            echo "Recent workflows (last 10):"
            echo "$ALL_WORKFLOWS" | jq -r 'sort_by(.launchTime // .launch_time) | reverse | .[] | "\(.status)\t\(.name // "unknown")\t\(.label // "unknown")"' 2>/dev/null | head -10 | nl -w 3 -s '. ' | while IFS=$'\t' read -r num status wrapper exp_label; do
                case "$status" in
                    *[Rr]unning*|*[Ss]tarted*)
                        printf "${YELLOW}%s${NC} %-15s %-20s %s\n" "$num" "$status" "$wrapper" "$exp_label"
                        ;;
                    *[Cc]omplete*|*[Ss]uccess*|*[Dd]one*)
                        printf "${GREEN}%s${NC} %-15s %-20s %s\n" "$num" "$status" "$wrapper" "$exp_label"
                        ;;
                    *[Ff]ail*|*[Ee]rror*)
                        printf "${RED}%s${NC} %-15s %-20s %s\n" "$num" "$status" "$wrapper" "$exp_label"
                        ;;
                    *)
                        printf "${BLUE}%s${NC} %-15s %-20s %s\n" "$num" "$status" "$wrapper" "$exp_label"
                        ;;
                esac
            done
        else
            echo -e "${RED}No workflow data available${NC}"
        fi

        echo ""
        echo -e "${YELLOW}Tip: Run ./check_status.sh -h $XNAT_HOST -u <user> -p <pass> -j $LARGEST_PROJECT -r today for detailed monitoring${NC}"
    fi
fi
