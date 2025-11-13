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
    echo "Usage: $0 -h <XNAT_HOST> -u <USERNAME> -p <PASSWORD> [-j <PROJECT_ID>] [-c <CONTAINER_NAME>] [-m <MAX_JOBS>] [-r <REPORT_PROJECT>]"
    echo "  -h  XNAT host (e.g., https://xnat.example.com)"
    echo "  -u  Username"
    echo "  -p  Password"
    echo "  -j  Project ID to test (optional - will show selection if not provided)"
    echo "  -c  Container name to run (optional - will list if not provided)"
    echo "  -m  Maximum number of jobs to submit (optional - defaults to all experiments)"
    echo "  -r  Report project ID to upload results to (optional - creates BATCH_TESTS resource)"
    exit 1
}

# Parse arguments
while getopts "h:u:p:j:c:m:r:" opt; do
    case $opt in
        h) XNAT_HOST="$OPTARG" ;;
        u) USERNAME="$OPTARG" ;;
        p) PASSWORD="$OPTARG" ;;
        j) LARGEST_PROJECT="$OPTARG" ;;
        c) CONTAINER_NAME="$OPTARG" ;;
        m) MAX_JOBS="$OPTARG" ;;
        r) REPORT_PROJECT="$OPTARG" ;;
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

# Step 2: Select project first (skip if -j provided)
if [ -z "$LARGEST_PROJECT" ]; then
    echo -e "${YELLOW}[2/5] Project selection...${NC}"
    echo "Fetching projects list..."
    PROJECTS=$(curl -s -b "JSESSIONID=$JSESSION" "${XNAT_HOST}/data/projects?format=json")

    PROJECT_COUNT=$(echo "$PROJECTS" | jq -r '.ResultSet.Result[] | .ID' | wc -l | tr -d ' ')
    echo "Found $PROJECT_COUNT projects. Counting experiments for each..."
    echo ""

    # Get experiment counts for each project using filtered queries with progress indicator
    PROJECT_COUNTS=$(echo "$PROJECTS" | jq -r '.ResultSet.Result[] | .ID' | {
        COUNTER=0
        while read -r PROJECT_ID; do
            COUNTER=$((COUNTER + 1))
            echo -ne "\r${YELLOW}Progress: $COUNTER/$PROJECT_COUNT projects checked...${NC}  " >&2
            # Use ?project= filter for more efficient server-side filtering
            EXP_COUNT=$(curl -s -b "JSESSIONID=$JSESSION" "${XNAT_HOST}/data/experiments?project=${PROJECT_ID}&format=json" | jq -r '.ResultSet.totalRecords // 0')
            echo "$EXP_COUNT:$PROJECT_ID"
        done
        echo "" >&2
    } | sort -rn)

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
else
    echo -e "${YELLOW}[2/5] Project selection...${NC}"
    echo "Using specified project: $LARGEST_PROJECT"
fi

# Get experiment count for selected project
MAX_EXPERIMENTS_RESPONSE=$(curl -s -b "JSESSIONID=$JSESSION" "${XNAT_HOST}/data/experiments?project=${LARGEST_PROJECT}&format=json")

# Check if response is valid JSON
if ! echo "$MAX_EXPERIMENTS_RESPONSE" | jq empty 2>/dev/null; then
    echo -e "${RED}Failed to retrieve experiments for project: $LARGEST_PROJECT${NC}"
    echo "Response: $MAX_EXPERIMENTS_RESPONSE"
    echo ""
    echo "This may indicate an invalid project ID."
    exit 1
fi

MAX_EXPERIMENTS=$(echo "$MAX_EXPERIMENTS_RESPONSE" | jq -r '.ResultSet.totalRecords // 0')

if [ "$MAX_EXPERIMENTS" = "0" ]; then
    echo -e "${RED}Error: Project $LARGEST_PROJECT has 0 experiments${NC}"
    echo ""
    echo "This project cannot be used for batch testing."
    echo "Please select a different project with experiments."
    exit 1
fi

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

# Validate JSON response
if ! echo "$EXPERIMENTS" | jq empty 2>/dev/null; then
    echo -e "${RED}Failed to retrieve experiments from project: $LARGEST_PROJECT${NC}"
    echo "Response: $EXPERIMENTS"
    echo ""
    echo -e "${YELLOW}This usually means the project ID is invalid.${NC}"
    echo "Please verify the project ID and try again."
    exit 1
fi

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

# Initialize timing and logging
BATCH_START_TIME=$(date +%s)
BATCH_START_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
LOG_DIR="logs/$(date '+%Y-%m-%d')"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/batch_test_$(date '+%H%M%S').log"

SUCCESS_COUNT=0
FAIL_COUNT=0
RESULTS_FILE="/tmp/batch_results_$$.txt"
TIMING_FILE="/tmp/batch_timing_$$.txt"

# Write log header
cat > "$LOG_FILE" <<EOF
=================================================================
XNAT Batch Performance Test Log
=================================================================
Test Started: $BATCH_START_TIMESTAMP
Host: $XNAT_HOST
User: $USERNAME
Project: $LARGEST_PROJECT ($MAX_EXPERIMENTS total experiments)
Container: $CONTAINER_NAME (Wrapper ID: $WRAPPER_ID)
Experiments to Process: $EXPERIMENT_COUNT
Max Jobs Limit: ${MAX_JOBS:-None (processing all)}
=================================================================

EOF

echo ""
echo "Logging to: $LOG_FILE"
echo ""

echo "$EXPERIMENT_IDS" | while read -r EXP_ID; do
    JOB_START_TIME=$(date +%s.%N)
    # Use form data (not JSON) with context=session parameter
    RESPONSE=$(curl -s -X POST \
        -b "JSESSIONID=$JSESSION" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        "${XNAT_HOST}/xapi/wrappers/${WRAPPER_ID}/root/xnat:imageSessionData/launch" \
        -d "context=session&session=${EXP_ID}")

    JOB_END_TIME=$(date +%s.%N)
    JOB_DURATION=$(echo "$JOB_END_TIME - $JOB_START_TIME" | bc)
    JOB_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    # Check if response is HTML (error page) or JSON
    if echo "$RESPONSE" | grep -q "<!doctype html"; then
        ERROR_TITLE=$(echo "$RESPONSE" | grep -oP '(?<=<title>)[^<]+' | head -1)
        echo -e "${RED}✗${NC} $EXP_ID: $ERROR_TITLE"
        echo "FAIL" >> "$RESULTS_FILE"
        echo "$JOB_DURATION" >> "$TIMING_FILE"

        # Log to file
        cat >> "$LOG_FILE" <<EOF
[$JOB_TIMESTAMP] FAIL - $EXP_ID
  Duration: ${JOB_DURATION}s
  Error: $ERROR_TITLE

EOF
    elif echo "$RESPONSE" | jq empty 2>/dev/null; then
        # Valid JSON response - check for success
        STATUS=$(echo "$RESPONSE" | jq -r '.status // "unknown"')
        if [ "$STATUS" = "success" ]; then
            WORKFLOW_ID=$(echo "$RESPONSE" | jq -r '.["workflow-id"] // "pending"')
            echo -e "${GREEN}✓${NC} $EXP_ID (workflow: $WORKFLOW_ID)"
            echo "SUCCESS" >> "$RESULTS_FILE"
            echo "$JOB_DURATION" >> "$TIMING_FILE"

            # Log to file
            cat >> "$LOG_FILE" <<EOF
[$JOB_TIMESTAMP] SUCCESS - $EXP_ID
  Duration: ${JOB_DURATION}s
  Workflow ID: $WORKFLOW_ID

EOF
        else
            ERROR_MSG=$(echo "$RESPONSE" | jq -r '.message // .error // "Unknown error"')
            echo -e "${RED}✗${NC} $EXP_ID: $ERROR_MSG"
            echo "FAIL" >> "$RESULTS_FILE"
            echo "$JOB_DURATION" >> "$TIMING_FILE"

            # Log to file
            cat >> "$LOG_FILE" <<EOF
[$JOB_TIMESTAMP] FAIL - $EXP_ID
  Duration: ${JOB_DURATION}s
  Error: $ERROR_MSG

EOF
        fi
    else
        echo -e "${RED}✗${NC} $EXP_ID: Invalid response"
        echo "FAIL" >> "$RESULTS_FILE"
        echo "$JOB_DURATION" >> "$TIMING_FILE"

        # Log to file
        cat >> "$LOG_FILE" <<EOF
[$JOB_TIMESTAMP] FAIL - $EXP_ID
  Duration: ${JOB_DURATION}s
  Error: Invalid response

EOF
    fi
done

BATCH_END_TIME=$(date +%s)
BATCH_END_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
TOTAL_DURATION=$((BATCH_END_TIME - BATCH_START_TIME))

# Count results from file (since while loop runs in subshell)
if [ -f "$RESULTS_FILE" ]; then
    SUCCESS_COUNT=$(grep -c "SUCCESS" "$RESULTS_FILE" 2>/dev/null || echo "0")
    FAIL_COUNT=$(grep -c "FAIL" "$RESULTS_FILE" 2>/dev/null || echo "0")
    rm "$RESULTS_FILE"
else
    SUCCESS_COUNT=0
    FAIL_COUNT=0
fi

# Ensure counts are numeric (handle empty strings)
SUCCESS_COUNT=${SUCCESS_COUNT:-0}
FAIL_COUNT=${FAIL_COUNT:-0}

# Calculate timing statistics
if [ -f "$TIMING_FILE" ]; then
    AVG_DURATION=$(awk '{ total += $1; count++ } END { if (count > 0) print total/count; else print 0 }' "$TIMING_FILE")
    MIN_DURATION=$(sort -n "$TIMING_FILE" | head -1)
    MAX_DURATION=$(sort -n "$TIMING_FILE" | tail -1)
    rm "$TIMING_FILE"
else
    AVG_DURATION=0
    MIN_DURATION=0
    MAX_DURATION=0
fi

# Ensure all numeric variables are set (handle empty strings)
EXPERIMENT_COUNT=${EXPERIMENT_COUNT:-0}
TOTAL_DURATION=${TOTAL_DURATION:-0}
AVG_DURATION=${AVG_DURATION:-0}
MIN_DURATION=${MIN_DURATION:-0}
MAX_DURATION=${MAX_DURATION:-0}

# Calculate percentages for log file
if [ "$EXPERIMENT_COUNT" -gt 0 ] 2>/dev/null; then
    LOG_SUCCESS_PCT=$(awk "BEGIN {printf \"%.1f\", ($SUCCESS_COUNT/$EXPERIMENT_COUNT)*100}" 2>/dev/null || echo "0.0")
    LOG_FAIL_PCT=$(awk "BEGIN {printf \"%.1f\", ($FAIL_COUNT/$EXPERIMENT_COUNT)*100}" 2>/dev/null || echo "0.0")
else
    LOG_SUCCESS_PCT="0.0"
    LOG_FAIL_PCT="0.0"
fi

LOG_DURATION_MIN=$(awk "BEGIN {printf \"%.1f\", $TOTAL_DURATION/60}" 2>/dev/null || echo "0.0")

if [ "$TOTAL_DURATION" -gt 0 ] 2>/dev/null; then
    LOG_THROUGHPUT=$(awk "BEGIN {printf \"%.2f\", $EXPERIMENT_COUNT/$TOTAL_DURATION}" 2>/dev/null || echo "0.00")
else
    LOG_THROUGHPUT="0.00"
fi

# Write summary to log
cat >> "$LOG_FILE" <<EOF
=================================================================
Test Summary
=================================================================
Test Completed: $BATCH_END_TIMESTAMP
Test Duration: ${TOTAL_DURATION}s (${LOG_DURATION_MIN} minutes)

Test Configuration:
  Project: $LARGEST_PROJECT ($MAX_EXPERIMENTS total experiments)
  Container: $CONTAINER_NAME (Wrapper ID: $WRAPPER_ID)
  Max Jobs Limit: ${MAX_JOBS:-None}
  Host: $XNAT_HOST
  User: $USERNAME

Results:
  Jobs Submitted: $EXPERIMENT_COUNT
  Successful: $SUCCESS_COUNT (${LOG_SUCCESS_PCT}%)
  Failed: $FAIL_COUNT (${LOG_FAIL_PCT}%)

Performance Metrics:
  Total Duration: ${TOTAL_DURATION}s
  Average Job Submission Time: ${AVG_DURATION}s
  Fastest Submission: ${MIN_DURATION}s
  Slowest Submission: ${MAX_DURATION}s
  Throughput: ${LOG_THROUGHPUT} jobs/sec
=================================================================
EOF

echo ""
echo -e "${GREEN}=== BATCH SUBMISSION COMPLETE ===${NC}"
echo ""
echo "Project: $LARGEST_PROJECT ($MAX_EXPERIMENTS experiments)"
echo "Container: $CONTAINER_NAME (ID: $WRAPPER_ID)"
echo "Jobs Submitted: $EXPERIMENT_COUNT"
echo ""
echo "Submission Results:"
if [ "$EXPERIMENT_COUNT" -gt 0 ] 2>/dev/null; then
    SUCCESS_PCT=$(awk "BEGIN {printf \"%.1f\", ($SUCCESS_COUNT/$EXPERIMENT_COUNT)*100}" 2>/dev/null || echo "0.0")
    FAIL_PCT=$(awk "BEGIN {printf \"%.1f\", ($FAIL_COUNT/$EXPERIMENT_COUNT)*100}" 2>/dev/null || echo "0.0")
else
    SUCCESS_PCT="0.0"
    FAIL_PCT="0.0"
fi
echo "  Successfully Queued: $SUCCESS_COUNT (${SUCCESS_PCT}%)"
echo "  Failed to Queue: $FAIL_COUNT (${FAIL_PCT}%)"
echo ""
echo "Submission Performance:"
DURATION_MIN=$(awk "BEGIN {printf \"%.1f\", $TOTAL_DURATION/60}" 2>/dev/null || echo "0.0")
if [ "$TOTAL_DURATION" -gt 0 ] 2>/dev/null; then
    THROUGHPUT=$(awk "BEGIN {printf \"%.2f\", $EXPERIMENT_COUNT/$TOTAL_DURATION}" 2>/dev/null || echo "0.00")
else
    THROUGHPUT="0.00"
fi
echo "  Submission Duration: ${TOTAL_DURATION}s (${DURATION_MIN} min)"
echo "  Avg Time per Job: ${AVG_DURATION}s"
echo "  Submission Throughput: ${THROUGHPUT} jobs/sec"
echo ""
echo -e "${YELLOW}Full log saved to: $LOG_FILE${NC}"
echo ""

# Wait for jobs to complete
if [ "$SUCCESS_COUNT" -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}=== MONITORING JOB EXECUTION ===${NC}"
    echo ""
    echo "Waiting for jobs to complete (checking every 10 seconds)..."
    echo "Press Ctrl+C to stop monitoring and continue"
    echo ""

    WORKFLOW_START_TIME=$(date +%s)
    LAST_CHECK_TIME=$WORKFLOW_START_TIME
    CHECK_COUNT=0

    while true; do
        sleep 10
        CHECK_COUNT=$((CHECK_COUNT + 1))
        ELAPSED=$(($(date +%s) - WORKFLOW_START_TIME))
        ELAPSED_MIN=$(awk "BEGIN {printf \"%.1f\", $ELAPSED/60}")

        echo -ne "\r${YELLOW}Check $CHECK_COUNT (${ELAPSED_MIN} min elapsed) - Fetching workflow status...${NC}  "

        # Fetch workflows with pagination (may need multiple pages)
        ALL_WORKFLOWS="[]"
        PAGE=1
        MAX_PAGES=10

        while [ $PAGE -le $MAX_PAGES ]; do
            PAGE_WORKFLOWS=$(curl -s -X POST \
                -b "JSESSIONID=$JSESSION" \
                -H "Content-Type: application/json" \
                -H "X-Requested-With: XMLHttpRequest" \
                --max-time 30 \
                "${XNAT_HOST}/xapi/workflows" \
                -d "{\"page\":$PAGE,\"id\":\"$LARGEST_PROJECT\",\"data_type\":\"xnat:projectData\",\"sortable\":true,\"days\":1}" 2>/dev/null)

            if [ -z "$PAGE_WORKFLOWS" ]; then
                break
            fi

            # Extract items array
            PAGE_ITEMS=$(echo "$PAGE_WORKFLOWS" | jq 'if type == "array" then . else .items // .workflows // [] end' 2>/dev/null)
            PAGE_COUNT=$(echo "$PAGE_ITEMS" | jq 'length' 2>/dev/null)

            if [ -z "$PAGE_COUNT" ] || [ "$PAGE_COUNT" -eq 0 ]; then
                break
            fi

            # Merge with accumulated workflows
            ALL_WORKFLOWS=$(echo "$ALL_WORKFLOWS" "$PAGE_ITEMS" | jq -s '.[0] + .[1]' 2>/dev/null)

            # If page returned less than 50, we've reached the end
            if [ "$PAGE_COUNT" -lt 50 ]; then
                break
            fi

            PAGE=$((PAGE + 1))
        done

        if [ "$ALL_WORKFLOWS" = "[]" ]; then
            echo -ne "\r${YELLOW}No workflows found yet, waiting...${NC}                              "
            continue
        fi

        # Filter workflows to only those from our batch (after BATCH_START_TIME)
        BATCH_WORKFLOWS=$(echo "$ALL_WORKFLOWS" | jq --arg container "$CONTAINER_NAME" --argjson start_time "$BATCH_START_TIME" '
            map(select(
                (.pipelineName // .pipeline_name // "") == $container and
                ((.launchTime // .launch_time // 0) / 1000) >= $start_time
            ))
        ' 2>/dev/null)

        TOTAL_WORKFLOWS=$(echo "$BATCH_WORKFLOWS" | jq 'length' 2>/dev/null)

        if [ -z "$TOTAL_WORKFLOWS" ] || [ "$TOTAL_WORKFLOWS" = "0" ]; then
            echo -ne "\r${YELLOW}No workflows found yet, waiting...${NC}                              "
            continue
        fi

        # Count by status
        RUNNING=$(echo "$BATCH_WORKFLOWS" | jq '[.[] | select(.status | test("Running|Started"; "i"))] | length' 2>/dev/null)
        COMPLETE=$(echo "$BATCH_WORKFLOWS" | jq '[.[] | select(.status | test("Complete|Success|Done"; "i"))] | length' 2>/dev/null)
        FAILED=$(echo "$BATCH_WORKFLOWS" | jq '[.[] | select(.status | test("Fail|Error"; "i"))] | length' 2>/dev/null)
        PENDING=$(echo "$BATCH_WORKFLOWS" | jq '[.[] | select(.status | test("Pending|Queued"; "i"))] | length' 2>/dev/null)

        # Clean up display line
        echo -ne "\r                                                                                           \r"

        echo "Check $CHECK_COUNT (${ELAPSED_MIN} min): Found $TOTAL_WORKFLOWS workflows - Running: ${RUNNING:-0}, Complete: ${COMPLETE:-0}, Failed: ${FAILED:-0}, Pending: ${PENDING:-0}"

        # Check if all jobs are done (none running or pending)
        if [ "${RUNNING:-0}" -eq 0 ] && [ "${PENDING:-0}" -eq 0 ] && [ "$TOTAL_WORKFLOWS" -ge "$SUCCESS_COUNT" ]; then
            echo ""
            echo -e "${GREEN}✓ All jobs completed!${NC}"
            echo ""

            # Show final status summary
            echo "Execution Results:"
            echo "  Complete: ${COMPLETE:-0}"
            echo "  Failed: ${FAILED:-0}"
            echo ""
            echo "Execution Performance:"
            echo "  Execution Duration: ${ELAPSED}s (${ELAPSED_MIN} min)"
            echo "  Total Time (Submission + Execution): $((TOTAL_DURATION + ELAPSED))s ($(awk "BEGIN {printf \"%.1f\", ($TOTAL_DURATION + $ELAPSED)/60}")min)"
            echo ""

            # Update log file with execution time
            TOTAL_WITH_EXECUTION=$((TOTAL_DURATION + ELAPSED))
            TOTAL_WITH_EXECUTION_MIN=$(awk "BEGIN {printf \"%.1f\", $TOTAL_WITH_EXECUTION/60}" 2>/dev/null || echo "0.0")

            cat >> "$LOG_FILE" <<EOF

=================================================================
Job Execution Monitoring
=================================================================
Execution Time: ${ELAPSED}s (${ELAPSED_MIN} minutes)
Final Status: ${COMPLETE:-0} Complete, ${FAILED:-0} Failed
Total Time (Submission + Execution): ${TOTAL_WITH_EXECUTION}s (${TOTAL_WITH_EXECUTION_MIN} minutes)
=================================================================
EOF

            # Store workflows for display below
            FINAL_WORKFLOWS="$BATCH_WORKFLOWS"
            break
        fi
    done
fi

# Display final workflow details if we monitored
if [ -n "$FINAL_WORKFLOWS" ]; then
    echo "Recent completed workflows (last 10):"
    echo "$FINAL_WORKFLOWS" | jq -r 'sort_by(.launchTime // .launch_time) | reverse | .[] | "\(.status)\t\(.name // "unknown")\t\(.label // "unknown")"' 2>/dev/null | head -10 | nl -w 3 -s '. ' | while IFS=$'\t' read -r num status wrapper exp_label; do
        case "$status" in
            *[Cc]omplete*|*[Ss]uccess*|*[Dd]one*)
                printf "${GREEN}%s${NC} %-15s %-20s %s\n" "$num" "$status" "$wrapper" "$exp_label"
                ;;
            *[Ff]ail*|*[Ee]rror*)
                printf "${RED}%s${NC} %-15s %-20s %s\n" "$num" "$status" "$wrapper" "$exp_label"
                ;;
            *)
                printf "%s %-15s %-20s %s\n" "$num" "$status" "$wrapper" "$exp_label"
                ;;
        esac
    done
    echo ""
fi

# Offer to monitor job status (if we didn't already monitor)
if [ "$SUCCESS_COUNT" -gt 0 ] && [ -z "$FINAL_WORKFLOWS" ]; then
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

# Generate and upload HTML report if requested
if [ -n "$REPORT_PROJECT" ]; then
    echo ""
    echo -e "${YELLOW}=== GENERATING HTML REPORT ===${NC}"
    echo ""

    # Check if generate_html_report.sh exists
    if [ -f "./generate_html_report.sh" ]; then
        # Generate and upload report
        ./generate_html_report.sh \
            -l "$LOG_FILE" \
            -h "$XNAT_HOST" \
            -u "$USERNAME" \
            -p "$PASSWORD" \
            -r "$REPORT_PROJECT"
    else
        echo -e "${RED}generate_html_report.sh not found${NC}"
        echo "Skipping HTML report generation"
    fi
fi
